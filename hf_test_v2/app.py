from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def read_root():
    return {"status": "success", "message": "HF Space is working!"}

@app.get("/health")
def health():
    return {"status": "ok"}
