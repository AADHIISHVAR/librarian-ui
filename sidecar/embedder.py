import hashlib
import math
import numpy as np
import requests
import os
from dotenv import load_dotenv

load_dotenv()
HF_TOKEN = os.getenv("HF_TOKEN")
MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
API_URL = f"https://api-inference.huggingface.co/pipeline/feature-extraction/{MODEL_ID}"


def _fallback_embedding(text: str, task: str, dim: int = 384) -> list[float]:
    """
    Deterministic lightweight embedding fallback.
    Uses repeated SHA-256 digests to fill a 384-d vector and L2-normalizes it.
    """
    seed = f"{task}: {text}".encode("utf-8")
    values = []
    counter = 0
    while len(values) < dim:
        digest = hashlib.sha256(seed + counter.to_bytes(4, "little")).digest()
        for b in digest:
            values.append((b / 255.0) * 2.0 - 1.0)
            if len(values) >= dim:
                break
        counter += 1
    arr = np.array(values, dtype=np.float32)
    norm = math.sqrt(float(np.dot(arr, arr)))
    if norm > 0:
        arr = arr / norm
    return arr.tolist()


def get_embedding(text: str, task: str = "search_query") -> list[float]:
    if not HF_TOKEN:
        print("[embedder] No HF_TOKEN found, using fallback.")
        return _fallback_embedding(text, task)

    prefixed = f"{task}: {text}"
    try:
        headers = {"Authorization": f"Bearer {HF_TOKEN}"}
        response = requests.post(
            API_URL, headers=headers, json={"inputs": prefixed}, timeout=10
        )

        if response.status_code == 200:
            vector = response.json()
            # HF API can return a list of lists
            if (
                isinstance(vector, list)
                and len(vector) > 0
                and isinstance(vector[0], list)
            ):
                return vector[0]
            return vector
        else:
            print(f"[embedder] API error {response.status_code}: {response.text}")
    except Exception as e:
        print(f"[embedder] API request failed: {e}")

    return _fallback_embedding(text, task)
