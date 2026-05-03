from sentence_transformers import SentenceTransformer

# loads once at startup — ~280MB, stays in memory
_model = SentenceTransformer(
    "nomic-ai/nomic-embed-text-v1.5",
    trust_remote_code=True
)

def get_embedding(text: str, task: str = "search_query") -> list[float]:
    prefixed = f"{task}: {text}"
    vector   = _model.encode(prefixed, normalize_embeddings=True)
    return vector.tolist()
