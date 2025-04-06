import json
import os
import tempfile
import logging
from datetime import datetime
from firebase_admin import credentials, firestore, initialize_app
from firebase_functions import https_fn, storage_fn, options
from google.cloud import storage
from google.cloud import vision_v1
import spacy
from spacy.matcher import PhraseMatcher
from openai import OpenAI
import re
import google.generativeai as genai  # Added for Gemini API

# Configure logging to output to Cloud Logging
logger = logging.getLogger('resume-parsing')
logger.setLevel(logging.INFO)  # Ensure INFO level logs are captured
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
logger.addHandler(handler)

# Initialize Firebase Admin SDK
logger.info("Initializing Firebase Admin SDK...")
try:
    initialize_app(credentials.ApplicationDefault())
    logger.info("Firebase Admin SDK initialized successfully.")
except Exception as e:
    logger.error(f"Failed to initialize Firebase Admin SDK: {str(e)}")
    raise

# Log environment variables for debugging
logger.info(f"Environment variables: {dict(os.environ)}")

# Initialize OpenAI client using environment variable
openai_api_key = os.environ.get("OPENAI_API_KEY")
if not openai_api_key:
    logger.warning("OpenAI API key not found in environment variables.")
openai_client = OpenAI(api_key=openai_api_key) if openai_api_key else None

# Globals
db = None
nlp = None
job_title_matcher = None
skills_matcher = None
education_matcher = None
field_matcher = None
certification_matcher = None

def init_services(load_spacy=False):
    global db, nlp, job_title_matcher, skills_matcher, education_matcher, field_matcher, certification_matcher
    try:
        if db is None:
            logger.info("Initializing Firestore client...")
            db = firestore.client()
            logger.info("Firestore client initialized successfully.")

        if load_spacy and nlp is None:
            logger.info("Initializing spaCy model...")
            nlp = spacy.load("en_core_web_sm")
            logger.info("spaCy model initialized successfully.")

            job_title_matcher = PhraseMatcher(nlp.vocab)
            job_titles = [
                "Software Engineer", "Senior Software Engineer", "Product Manager", "Data Scientist",
                "Project Manager", "DevOps Engineer", "System Administrator", "Web Developer",
                "Frontend Developer", "Backend Developer", "Full Stack Developer", "Machine Learning Engineer"
            ]
            job_title_patterns = [nlp(title) for title in job_titles]
            job_title_matcher.add("JOB_TITLE", job_title_patterns)
            logger.info("PhraseMatcher initialized for job titles.")

            skills_matcher = PhraseMatcher(nlp.vocab)
            skills = [
                "Python", "Java", "JavaScript", "C++", "SQL", "AWS", "Docker", "Kubernetes",
                "React", "Angular", "Node.js", "Machine Learning", "Data Analysis", "Project Management",
                "Git", "Linux", "MySQL", "MongoDB", "TensorFlow", "Pandas", "NumPy", "Agile", "Scrum"
            ]
            skills_patterns = [nlp(skill) for skill in skills]
            skills_matcher.add("SKILL", skills_patterns)
            logger.info("PhraseMatcher initialized for skills/tools.")

            education_matcher = PhraseMatcher(nlp.vocab)
            education_levels = [
                "Bachelor", "Master", "PhD", "Associate", "Diploma", "B.S.", "M.S.", "MBA", "B.A.", "M.A."
            ]
            education_patterns = [nlp(level) for level in education_levels]
            education_matcher.add("EDUCATION_LEVEL", education_patterns)
            logger.info("PhraseMatcher initialized for education levels.")

            field_matcher = PhraseMatcher(nlp.vocab)
            fields = [
                "Computer Science", "Engineering", "Information Technology", "Business Administration",
                "Mathematics", "Physics", "Economics", "Electrical Engineering", "Mechanical Engineering",
                "Data Science", "Software Engineering"
            ]
            field_patterns = [nlp(field) for field in fields]
            field_matcher.add("EDUCATION_FIELD", field_patterns)
            logger.info("PhraseMatcher initialized for education fields.")

            certification_matcher = PhraseMatcher(nlp.vocab)
            certifications = [
                "AWS Certified Solutions Architect", "PMP", "Certified ScrumMaster", "Google Cloud Professional",
                "Microsoft Certified", "Cisco Certified", "CompTIA Security+", "Certified Ethical Hacker",
                "Oracle Certified", "Salesforce Certified"
            ]
            certification_patterns = [nlp(cert) for cert in certifications]
            certification_matcher.add("CERTIFICATION", certification_patterns)
            logger.info("PhraseMatcher initialized for certifications.")
    except Exception as e:
        logger.error(f"Error in init_services: {str(e)}")
        raise

@https_fn.on_call(region="asia-south2")
def upload_resume(req: https_fn.CallableRequest):
    logger.info("Starting upload_resume function...")
    init_services(load_spacy=False)
    try:
        uid = req.auth.uid
        filename = req.data.get("filename")
        if not filename:
            logger.error("Missing filename in request")
            raise ValueError("Missing filename")

        logger.info(f"Verifying upload for UID: {uid}, Filename: {filename}")

        # Verify the file exists in Firebase Storage
        bucket_name = "login-app-b82df.firebasestorage.app"
        file_path = f"resumes/{uid}/{filename}"
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_path)

        if not blob.exists():
            logger.error(f"File not found in Storage at gs://{bucket_name}/{file_path}")
            raise https_fn.HttpsError('not-found', f"Uploaded file not found for user {uid}")

        logger.info(f"Upload verified successfully for UID: {uid}, Filename: {filename}")
        return {"status": "success", "message": "Resume uploaded successfully"}
    except Exception as e:
        logger.error(f"Error in upload_resume: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", timeout_sec=120, memory=512)
def parse_resume_by_vision(req: https_fn.CallableRequest):
    logger.info("Starting parse_resume_by_vision function...")
    init_services(load_spacy=False)
    try:
        logger.info(f"Auth object: {req.auth}")
        if not req.auth:
            logger.error("User is not authenticated.")
            raise https_fn.HttpsError('unauthenticated', 'User must be authenticated')

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")

        bucket_name = "login-app-b82df.firebasestorage.app"
        file_path = f"resumes/{uid}/resume.pdf"
        output_dir = f"parsed_output/{uid}/"  # Use directory as prefix

        logger.info(f"Checking if PDF exists at gs://{bucket_name}/{file_path}...")
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_path)
        if not blob.exists():
            logger.error(f"PDF file does not exist at gs://{bucket_name}/{file_path}")
            raise https_fn.HttpsError('not-found', f"PDF file not found for user {uid}")

        client = vision_v1.ImageAnnotatorClient()
        mime_type = "application/pdf"

        gcs_source_uri = f"gs://{bucket_name}/{file_path}"
        gcs_dest_uri = f"gs://{bucket_name}/{output_dir}"  # Directory prefix for Vision API

        feature = vision_v1.Feature(type_=vision_v1.Feature.Type.DOCUMENT_TEXT_DETECTION)
        gcs_source = vision_v1.GcsSource(uri=gcs_source_uri)
        input_config = vision_v1.InputConfig(gcs_source=gcs_source, mime_type=mime_type)
        gcs_dest = vision_v1.GcsDestination(uri=gcs_dest_uri)
        output_config = vision_v1.OutputConfig(gcs_destination=gcs_dest)

        request = vision_v1.AsyncAnnotateFileRequest(
            features=[feature], input_config=input_config, output_config=output_config
        )

        logger.info("Sending request to Vision API...")
        operation = client.async_batch_annotate_files(requests=[request])
        logger.info("Waiting for Vision API operation to complete...")
        operation.result(timeout=60)
        logger.info("Vision API operation completed successfully.")

        # List files in the output directory
        blobs = bucket.list_blobs(prefix=output_dir)
        output_files = [blob.name for blob in blobs if blob.name.endswith(".json")]
        if not output_files:
            logger.error(f"No output files found in gs://{bucket_name}/{output_dir}")
            raise https_fn.HttpsError('internal', "Vision API did not produce output files")

        # Find the latest file (Vision API appends suffixes like output-1-to-1.json)
        latest_file = max(output_files, key=lambda x: x)
        logger.info(f"Latest output file: {latest_file}")

        # Rename the latest file to output-1-to-1.json
        target_path = f"parsed_output/{uid}/output-1-to-1.json"
        source_blob = bucket.blob(latest_file)
        bucket.rename_blob(source_blob, target_path)
        logger.info(f"Renamed {latest_file} to {target_path}")

        # Delete any other JSON files in the directory
        for file in output_files:
            if file != target_path:
                bucket.blob(file).delete()
                logger.info(f"Deleted old file: {file}")

        return {"status": "success", "message": "Vision parsing complete"}
    except Exception as e:
        logger.error(f"Error in parse_resume_by_vision: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512)
def extract_resume_fields(req: https_fn.CallableRequest):
    logger.info("Starting extract_resume_fields function...")
    init_services(load_spacy=True)
    try:
        uid = req.auth.uid
        logger.info(f"User UID: {uid}")
        bucket_name = "login-app-b82df.firebasestorage.app"
        output_path = f"parsed_output/{uid}/output-1-to-1.json"  # Always read from output-1-to-1.json

        logger.info(f"Checking for JSON file at gs://{bucket_name}/{output_path}...")
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(output_path)

        if not blob.exists():
            logger.error(f"No JSON file found at gs://{bucket_name}/{output_path}")
            raise https_fn.HttpsError('not-found', f"No parsed JSON file found for user {uid}")

        with tempfile.NamedTemporaryFile(delete=False) as temp:
            blob.download_to_file(temp)
            temp.flush()
            temp.seek(0)
            parsed_data = json.load(temp)
        logger.info("Parsed JSON downloaded successfully.")

        full_text = parsed_data['responses'][0]['fullTextAnnotation']['text']
        logger.info(f"Full text extracted: {full_text[:500]}...")

        doc = nlp(full_text)
        experience_pattern = r'(\d+)\s*(years|yrs)\s*(of)?\s*experience'
        experience_matches = re.findall(experience_pattern, full_text, re.IGNORECASE)
        years_of_experience = experience_matches[0][0] + " years" if experience_matches else "Not Found"

        job_title_matches = job_title_matcher(doc)
        job_titles = [doc[start:end].text for match_id, start, end in job_title_matches]
        job_title_pattern = r'(worked as|currently|last position as)\s*([A-Za-z\s]+)'
        job_title_regex_matches = re.findall(job_title_pattern, full_text, re.IGNORECASE)
        job_titles.extend([match[1].strip() for match in job_title_regex_matches])
        current_job_title = job_titles[0] if job_titles else "Not Found"

        description_keywords = ["project", "work", "responsibilities", "developed", "led", "managed"]
        sentences = [sent.text.strip() for sent in doc.sents]
        description_sentences = [sent for sent in sentences if any(keyword in sent.lower() for keyword in description_keywords)]
        brief_description = " ".join(description_sentences[:2]) if description_sentences else "Not Found"

        skills_matches = skills_matcher(doc)
        skills = [doc[start:end].text for match_id, start, end in skills_matches]

        education_matches = education_matcher(doc)
        education_levels = [doc[start:end].text for match_id, start, end in education_matches]
        field_matches = field_matcher(doc)
        education_fields = [doc[start:end].text for match_id, start, end in field_matches]
        education_level = education_levels[0] if education_levels else "Not Found"
        education_field = education_fields[0] if education_fields else "Not Found"
        highest_education = f"{education_level} in {education_field}" if education_level != "Not Found" and education_field != "Not Found" else "Not Found"

        certification_matches = certification_matcher(doc)
        certifications = [doc[start:end].text for match_id, start, end in certification_matches]
        cert_pattern = r'(certified in|certification in)\s*([A-Za-z\s]+)'
        cert_regex_matches = re.findall(cert_pattern, full_text, re.IGNORECASE)
        certifications.extend([match[1].strip() for match in cert_regex_matches])

        entities = {
            "current_job_title": current_job_title,
            "years_of_experience": years_of_experience,
            "brief_description": brief_description,
            "key_skills_tools": skills or ["Not Found"],
            "highest_education": highest_education,
            "certifications": certifications or ["Not Found"],
            "last_extracted": datetime.utcnow().isoformat(),
            "extracted_by": "spaCy"
        }

        doc_ref = db.collection("resume").document(uid)
        doc_ref.delete()
        doc_ref.set(entities, merge=False)
        return {"status": "success", "fields": entities}
    except Exception as e:
        logger.error(f"Error in extract_resume_fields: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512, secrets=["OPENAI_API_KEY"])
def extract_resume_openai(req: https_fn.CallableRequest):
    logger.info("Starting extract_resume_openai function...")
    try:
        init_services(load_spacy=False)
        if not openai_client:
            raise ValueError("OpenAI client not initialized.")
        if db is None:
            raise ValueError("Firestore client not initialized.")

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")
        bucket_name = "login-app-b82df.firebasestorage.app"
        output_path = f"parsed_output/{uid}/output-1-to-1.json"  # Always read from output-1-to-1.json

        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(output_path)

        if not blob.exists():
            logger.error(f"No JSON file found at gs://{bucket_name}/{output_path}")
            raise https_fn.HttpsError('not-found', f"No parsed JSON file found for user {uid}")

        with tempfile.NamedTemporaryFile(delete=False) as temp:
            blob.download_to_file(temp)
            temp.flush()
            temp.seek(0)
            parsed_data = json.load(temp)

        full_text = parsed_data['responses'][0]['fullTextAnnotation']['text']
        logger.info(f"Full text: {full_text[:500]}...")

        prompt = f"""
        Extract the following structured data from the resume text below and return it as a pure JSON string:
        - current_job_title: The current or last job title (string)
        - years_of_experience: Total years of work experience (string, e.g., "5 years")
        - brief_description: A brief description of work or projects (string, 1-2 sentences)
        - key_skills_tools: A list of key skills or tools (list of strings)
        - highest_education: Highest education level and field (string, e.g., "Bachelor in Computer Science")
        - certifications: A list of certification courses (list of strings)
        If a field cannot be found, use "Not Found" for strings or ["Not Found"] for lists.

        Resume text:
        {full_text}
        """

        response = openai_client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that extracts structured data from resumes and returns it as a pure JSON string."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=500,
            temperature=0.3
        )

        raw_response = response.choices[0].message.content
        logger.info(f"Raw OpenAI response: {raw_response}")

        json_match = re.search(r'\{.*\}', raw_response, re.DOTALL)
        json_str = json_match.group(0) if json_match else raw_response
        extracted_data = json.loads(json_str)

        extracted_data["last_extracted"] = datetime.utcnow().isoformat()
        extracted_data["extracted_by"] = "OpenAI"

        doc_ref = db.collection("resume").document(uid)
        doc_ref.delete()
        doc_ref.set(extracted_data, merge=False)
        return {"status": "success", "fields": extracted_data}
    except Exception as e:
        logger.error(f"Error in extract_resume_openai: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512, secrets=["OPENAI_API_KEY"])
def generate_jd(req: https_fn.CallableRequest):
    logger.info("Starting generate_jd function...")
    try:
        init_services(load_spacy=False)
        if not openai_client:
            raise ValueError("OpenAI client not initialized.")
        if db is None:
            logger.error("Firestore client (db) is None after init_services.")
            raise ValueError("Firestore client not initialized.")

        logger.info(f"Type of db: {type(db)}")

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")

        goal_ref = db.collection('udata').document(uid)
        logger.info(f"Goal ref: {goal_ref}")
        goal_doc = goal_ref.get()
        if not goal_doc.exists:
            logger.error(f"No goal data found for user {uid}")
            raise https_fn.HttpsError('not-found', "Goal data not found")

        goal_data = goal_doc.to_dict()
        company = goal_data.get('company', '')
        position = goal_data.get('position', '')
        location = goal_data.get('location', '')
        deadline = goal_data.get('deadline', '')

        resume_ref = db.collection('resume').document(uid)
        resume_doc = resume_ref.get()
        if not resume_doc.exists:
            logger.error(f"No resume data found for user {uid}")
            raise https_fn.HttpsError('not-found', "Resume data not found")

        resume_data = resume_doc.to_dict()
        experience = resume_data.get('years_of_experience', 'Not Found')

        prompt = f"""
        Generate a professional job description for a position at {company} as a {position}, located in {location}, requiring experience within range of 0.5 years from {experience}. Use current market trends and industry standards to create a realistic and appealing JD. Structure the response as a JSON object with:
        - "summary": A brief overview of the role (2-3 sentences).
        - "responsibilities": A list of 5-7 key duties (bullet points as text, e.g., "- Duty 1").
        - "qualifications": A list of 3-5 required qualifications (bullet points as text).
        - "skills": A list of 5-7 key skills (bullet points as text).
        - "relevance": A short explanation of why this role matters now (2-3 sentences).
        Tailor the content to the specific company, role, and location with smart analysis based on latest market insights. Return only the JSON object.
        """

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a job description expert with knowledge of 2025 market trends."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=1000,
            temperature=0.7,
        )

        raw_response = response.choices[0].message.content
        logger.info(f"Raw OpenAI response: {raw_response}")

        json_match = re.search(r'\{.*\}', raw_response, re.DOTALL)
        json_str = json_match.group(0) if json_match else raw_response
        jd_data = json.loads(json_str)

        db.collection('jd').document(uid).set(jd_data, merge=True)
        logger.info(f"JD saved to Firestore for user {uid}")

        return {"status": "success"}
    except Exception as e:
        logger.error(f"Error in generate_jd: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512, secrets=["OPENAI_API_KEY"])
def analyze_missing_skills(req: https_fn.CallableRequest):
    logger.info("Starting analyze_missing_skills function...")
    try:
        init_services(load_spacy=False)
        if not openai_client:
            raise ValueError("OpenAI client not initialized.")
        if db is None:
            raise ValueError("Firestore client not initialized.")

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")

        # Fetch JD from Firestore
        jd_doc = db.collection('jd').document(uid).get()
        if not jd_doc.exists:
            logger.error(f"No JD found for user {uid}")
            raise https_fn.HttpsError('not-found', "JD not found")

        jd_data = jd_doc.to_dict()
        jd_text = (
            f"Summary: {jd_data.get('summary', '')}\n"
            f"Responsibilities: {jd_data.get('responsibilities', '')}\n"
            f"Qualifications: {jd_data.get('qualifications', '')}\n"
            f"Skills: {jd_data.get('skills', '')}\n"
            f"Relevance: {jd_data.get('relevance', '')}"
        )

        # Fetch resume from Firestore
        resume_doc = db.collection('resume').document(uid).get()
        if not resume_doc.exists:
            logger.error(f"No resume found for user {uid}")
            raise https_fn.HttpsError('not-found', "Resume not found")

        resume_data = resume_doc.to_dict()
        resume_text = (
            f"Job Title: {resume_data.get('current_job_title', '')}\n"
            f"Experience: {resume_data.get('years_of_experience', '')}\n"
            f"Description: {resume_data.get('brief_description', '')}\n"
            f"Skills: {', '.join(resume_data.get('key_skills_tools', []))}\n"
            f"Education: {resume_data.get('highest_education', '')}\n"
            f"Certifications: {', '.join(resume_data.get('certifications', []))}"
        )

        # Open AI prompt
        prompt = f"""
        You are a career expert tasked with comparing a job description (JD) and a resume to identify gaps. Follow these steps:
        1. Extract all required skills, qualifications, and experiences from the JD, considering all sections (summary, responsibilities, qualifications, skills, relevance).
        2. Identify skills, qualifications, and experiences present in the resume, considering all sections (job title, experience, description, skills, education, certifications).
        3. Compare the two and identify:
           - "education_gap": If the JD's qualifications require a specific education level or field (e.g., "Bachelor's degree in Computer Science") that the resume's highest_education does not meet (e.g., "Diploma in Mechanical Engineering"), describe the mismatch as a string (e.g., "JD requires: Bachelor's degree in Computer Science; Resume has: Diploma in Mechanical Engineering"). If no mismatch, return "No education gap".
           - "high_priority_gaps": Critical non-skill requirements (e.g., certifications, core experiences) in the JD that are missing from the resume (e.g., "JD requires: AWS certification; Not found in resume").
           - "low_priority_gaps": Less critical non-skill requirements (e.g., nice-to-have experiences) in the JD that are missing from the resume (e.g., "JD requires: Experience with microservices architecture; Not found in resume").
           - Missing skills: Skills required by the JD but not present in the resume.
        4. Categorize missing skills into:
           - "technical_skills": Skills related to tools, technologies, or specific expertise (e.g., "Kubernetes", "Python").
           - "soft_skills": Skills related to interpersonal or behavioral traits (e.g., "Communication", "Problem-solving").
           Use your judgment to categorize skills and prioritize non-skill gaps based on their importance to the role.
        Return the result as a JSON object with "education_gap" (string), "high_priority_gaps" (list of strings), "low_priority_gaps" (list of strings), "technical_skills" (list of strings), and "soft_skills" (list of strings). Do not include any additional text or explanations.

        JD:
        {jd_text}

        Resume:
        {resume_text}
        """

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a career expert specializing in resume and JD analysis."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=1500,
            temperature=0.7,
        )

        raw_response = response.choices[0].message.content
        logger.info(f"Raw OpenAI response: {raw_response}")

        json_match = re.search(r'\{.*\}', raw_response, re.DOTALL)
        json_str = json_match.group(0) if json_match else raw_response
        analysis_data = json.loads(json_str)

        # Add timestamp and UID to the result
        analysis_data['uid'] = uid
        analysis_data['timestamp'] = datetime.utcnow().isoformat()

        # Store in Firestore (overwrite existing document)
        db.collection('skill_analysis').document(uid).set(analysis_data, merge=False)
        logger.info(f"Analysis saved to Firestore for user {uid}")

        return {"status": "success", "result": analysis_data}
    except Exception as e:
        logger.error(f"Error in analyze_missing_skills: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512, secrets=["OPENAI_API_KEY"])
def search_courses(req: https_fn.CallableRequest):
    logger.info("Starting search_courses function...")
    try:
        init_services(load_spacy=False)
        if not openai_client:
            raise ValueError("OpenAI client not initialized.")
        if db is None:
            raise ValueError("Firestore client not initialized.")

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")

        # Get the categorized skills from the request
        skills_data = req.data['skills']
        if not skills_data:
            logger.error("No skills provided for course search.")
            raise https_fn.HttpsError('invalid-argument', "Skills data is required.")

        # Open AI prompt with escaped curly braces
        prompt = f"""
        You are an expert in online education and course recommendations. I need to find courses to improve the following skills, categorized as follows:
        - Technical Skills: {', '.join(skills_data.get('Technical Skills', {}).keys()) or 'None'}
        - Soft Skills: {', '.join(skills_data.get('Soft Skills', {}).keys()) or 'None'}
        - High Priority Gaps: {', '.join(skills_data.get('High Priority Gaps', {}).keys()) or 'None'}
        - Low Priority Gaps: {', '.join(skills_data.get('Low Priority Gaps', {}).keys()) or 'None'}
        Search for courses on the following platforms, ensuring they are accessible in India:
        - Udemy: Find relevant courses with high ratings (4.5+ stars) and significant enrollments (e.g., 10,000+ students).
        - Coursera: Find courses from reputable institutions (e.g., universities or companies like Google, IBM).
        - YouTube: Identify authentic education channels with high views (e.g., 500,000+ views on relevant videos) and suggest either their playlists or create a playlist of the most relevant 3-5 videos for the skills.
        Additionally, if there are other well-known sources (e.g., edX, Udacity, LinkedIn Learning) with relevant courses for these skills, include those as well.
        For each course, provide:
        - Source (e.g., Udemy, Coursera, YouTube).
        - Course or playlist title.
        - Fee in Indian Rupees (INR) (e.g., "Free", "₹4150", "Subscription-based"). Convert USD to INR using an exchange rate of 1 USD = 83 INR.
        - Duration (e.g., "10 hours", "4 weeks").
        - Direct link (or a search link if a direct link isn't available).
        Provide the top 5 course or playlist suggestions per skill, categorized by the skill type (Technical Skills, Soft Skills, High Priority Gaps, Low Priority Gaps). Ensure the suggestions are recent (2024 or 2025) and relevant to the skills provided. Return the result as a JSON object with the structure:
        {{
          "Technical Skills": {{
            "Skill1": [{{"source": "...", "title": "...", "fee": "...", "duration": "...", "link": "..."}}, ...],
            ...
          }},
          "Soft Skills": {{...}},
          "High Priority Gaps": {{...}},
          "Low Priority Gaps": {{...}}
        }}
        """

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are an expert in online education and course recommendations."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=2000,
            temperature=0.7,
        )

        raw_response = response.choices[0].message.content
        logger.info(f"Raw OpenAI response: {raw_response}")

        json_match = re.search(r'\{.*\}', raw_response, re.DOTALL)
        json_str = json_match.group(0) if json_match else raw_response
        course_data = json.loads(json_str)

        return {"status": "success", "result": course_data}
    except Exception as e:
        logger.error(f"Error in search_courses: {str(e)}")
        return {"status": "failed", "error": str(e)}

@https_fn.on_call(region="asia-south2", memory=512, secrets=["GEMINI_API_KEY"])
def schedule_and_block_courses(req: https_fn.CallableRequest):
    logger.info("Starting schedule_and_block_courses function...")
    try:
        init_services(load_spacy=False)
        if db is None:
            raise ValueError("Firestore client not initialized.")

        uid = req.auth.uid
        logger.info(f"User UID: {uid}")

        data = req.data
        start_date = data.get("start_date")
        end_date = data.get("end_date")
        selected_days = data.get("selected_days", [])
        time_slot = data.get("time_slot")
        hours_per_day = data.get("hours_per_day", 2.0)

        courses_doc = db.collection('selected_courses').document(uid).get()
        if not courses_doc.exists:
            raise https_fn.HttpsError('not-found', "No selected courses found")

        courses_data = courses_doc.to_dict()
        total_hours = 0
        course_list = ""
        for category in ['technical_skills', 'soft_skills', 'high_priority_gaps', 'low_priority_gaps']:
            for skill, courses in courses_data.get(category, {}).items():
                for course in courses:
                    duration = course.get('duration', '0 hours')
                    hours = float(re.search(r'(\d+\.?\d*)', duration).group(1) if re.search(r'(\d+\.?\d*)', duration) else 0)
                    total_hours += hours
                    course_list += f"{course['title']} ({duration}), "

        # Use Gemini API
        gemini_api_key = os.environ.get("GEMINI_API_KEY")
        if not gemini_api_key:
            logger.error("Gemini API key not found in environment variables")
            raise ValueError("Gemini API key not found")

        logger.info("Configuring Gemini API...")
        genai.configure(api_key=gemini_api_key)
        model = genai.GenerativeModel("gemini-1.5-flash")

        prompt = f"""
        Create a schedule for completing these courses: {course_list.rstrip(', ')}
        Constraints:
        - Start date: {start_date}
        - End date: {end_date}
        - Preferred days: {', '.join(selected_days)}
        - Time slot: {time_slot}
        - Hours per day: {hours_per_day}
        - Total hours required: {total_hours}
        Return a JSON array with columns: Subject, Start Date, Start Time, End Date, End Time.
        Ensure Sundays are free if possible and the schedule fits the constraints.
        Return only the JSON array, no additional text.
        """

        response = model.generate_content(prompt)
        logger.info(f"Gemini response: {response.text}")

        if not response.text:
            raise ValueError("Gemini API returned an empty response")

        # Extract JSON array from the response
        json_match = re.search(r'\[.*\]', response.text, re.DOTALL)
        if not json_match:
            logger.error(f"Failed to find JSON array in Gemini response: {response.text}")
            raise ValueError("Gemini response does not contain a JSON array")

        json_str = json_match.group(0)
        try:
            schedule = json.loads(json_str)
            if not isinstance(schedule, list):
                raise ValueError("Gemini response is not a JSON array")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Gemini response as JSON: {json_str}")
            raise ValueError(f"Invalid JSON response from Gemini: {str(e)}")

        db.collection('schedules').document(uid).set({
            "schedule": schedule,
            "timestamp": datetime.utcnow().isoformat()
        }, merge=True)

        return {"status": "success"}
    except Exception as e:
        logger.error(f"Error in schedule_and_block_courses: {str(e)}")
        return {"status": "failed", "error": str(e)}