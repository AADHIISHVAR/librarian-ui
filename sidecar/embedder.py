import hashlib
import math
import numpy as np

_model = None
_has_sentence_transformers = False

try:
    from sentence_transformers import SentenceTransformer

    _model = SentenceTransformer(
        "nomic-ai/nomic-embed-text-v1.5",
        trust_remote_code=True,
    )
    _has_sentence_transformers = True
    print("[embedder] Loaded sentence-transformers model.")
except Exception as exc:
    # Build must stay green on constrained environments (HF).
    print(f"[embedder] sentence-transformers unavailable, using deterministic fallback: {exc}")


def _fallback_embedding(text: str, task: str, dim: int = 768) -> list[float]:
    """
    Deterministic lightweight embedding fallback.
    Uses repeated SHA-256 digests to fill a 768-d vector and L2-normalizes it.
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
    prefixed = f"{task}: {text}"
    if _has_sentence_transformers and _model is not None:
        vector = _model.encode(prefixed, normalize_embeddings=True)
        return vector.tolist()
    return _fallback_embedding(text, task)
