FROM python:3.11-slim

# Force Python stdout/stderr to be unbuffered so logs print in real-time
ENV PYTHONUNBUFFERED=1

# Install system dependencies (build-essential is required for compiling sqlite-vec)
RUN apt-get update && apt-get install -y \
    build-essential \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the sentence-transformers model during Docker build so it starts instantly
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')"

# Copy application and the AI-enriched database
COPY app.py .
COPY uniqueBooks_ai_enhances.db .

# Expose port 7860 (Hugging Face Spaces runs apps on port 7860)
EXPOSE 7860

# CMD to start the FastAPI server
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
