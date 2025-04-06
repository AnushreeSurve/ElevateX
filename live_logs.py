import subprocess
import time

while True:
    print("----- Latest Logs -----")
    subprocess.run([
        "gcloud", "functions", "logs", "read", "extract_resume_fields",
        "--region=asia-south2",
        "--limit=10",
        "--freshness=2m"
    ])
    time.sleep(5)
