@echo off
:loop
cls
gcloud functions logs read extract_resume_fields --region=asia-south2 --limit=10
timeout /t 5 >nul
goto loop
