# Use Python 3.13.5 as base image
FROM python:3.13.5

# Set the working directory inside the container
WORKDIR /app

# Copy only the backend code (optional, but clean)
COPY lib/ ./lib/

# If you have a requirements.txt for backend dependencies
# create it and uncomment the next line
# RUN pip install -r requirements.txt

# Expose the backend port (change 8000 if your backend uses another)
EXPOSE 8000

# Run your Python backend
CMD ["python", "lib/screens/app.py"]
