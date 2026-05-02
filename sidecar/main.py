from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from embedder import get_embedding
from generator import generate_response, generate_hyde_query
from db import search_books, setup_vec_table, get_conn, list_library_books, list_competitive_books

app = FastAPI(title="Librarian AI Sidecar")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080"],  # Trunk default port
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


def sync_vec_table():
    """Syncs the vec_books virtual table with the book_embeddings table."""
    conn = get_conn()
    try:
        count = conn.execute("SELECT count(*) FROM vec_books").fetchone()[0]
        if count == 0:
            print("[db] Populating vec_books virtual table from book_embeddings...")
            # Clean IDs during sync
            conn.execute(
                "INSERT INTO vec_books(accession_num, embedding) SELECT REPLACE(accession_num, \"'\", ''), embedding FROM book_embeddings"
            )
            conn.commit()
    except Exception as e:
        print(f"[db] Sync error: {e}")
    conn.close()


# create vec tables on startup if not already there
@app.on_event("startup")
def startup():
    setup_vec_table()
    sync_vec_table()
    print("[startup] Sidecar ready.")


class SearchRequest(BaseModel):
    prompt: str
    library: str = "all"  # "all" | "Central" | "MBA"
    top_k: int = 5

class ListBooksRequest(BaseModel):
    library: str
    query: str = None


def looks_like_title_search(prompt: str) -> bool:
    """
    If the prompt is short and doesn't contain
    intent words, treat it as a direct title search.
    """
    intent_words = [
        "want", "learn", "understand", "looking", "need", 
        "find", "about", "explain", "topic", "books", "suggest"
    ]
    prompt_lower = prompt.lower()
    
    # Increase word count limit — many titles are 6-10 words
    is_short = len(prompt.split()) <= 10
    
    # Use word boundary check for intent words to avoid partial matches
    has_intent = any(f" {w} " in f" {prompt_lower} " for w in intent_words)
    
    return is_short and not has_intent


@app.post("/search")
def search(req: SearchRequest):
    try:
        print(f"[search] Query: {req.prompt}")
        hyde_text = None

        if looks_like_title_search(req.prompt):
            # 1. Direct embed for titles (no HyDE noise)
            print(f"[search] Direct title search detected.")
            vector = get_embedding(req.prompt, task="search_query")
        else:
            # 1. HyDE expansion for intent/topic queries
            hyde_text = generate_hyde_query(req.prompt)
            print(f"[search] HyDE context: {hyde_text}")
            
            # Combine for better matching
            query_text = f"{req.prompt} {hyde_text}"
            vector = get_embedding(query_text, task="search_query")

        # 2. Vector search
        books = search_books(vector, req.library, req.top_k)
        
        # 3. Debug Print Scores
        print("[debug] Vector match scores:")
        for b in books:
            print(f"  {b['similarity']:.4f} -> {b['title']}")

        # 4. Fallback: If all scores are weak (< 0.6 for Cosine similarity), use SQL LIKE fallback
        current_max = max([b["similarity"] for b in books]) if books else 0.0
        if current_max < 0.6:
            print(f"[search] Weak vector scores ({current_max}). Falling back to title search...")
            from db import list_library_books # Reuse the list function for standard search
            fallback_books = list_library_books("all", req.prompt, limit=req.top_k)
            if fallback_books:
                # If we find title matches, replace the vector results
                books = fallback_books
                print(f"[search] Found {len(books)} matches via SQL fallback.")

        # 5. LLM generates conversational response
        reply = generate_response(req.prompt, books, hyde_context=hyde_text)

        return {"books": books, "reply": reply}

    except Exception as e:
        print(f"[search] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/list")
def list_books(req: ListBooksRequest):
    try:
        if req.library.lower() == "competitive":
            books = list_competitive_books(req.query)
        else:
            books = list_library_books(req.library, req.query)
        return books
    except Exception as e:
        print(f"[list] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


from typing import Optional

class AdvancedSearchRequest(BaseModel):
    acc_no: Optional[str] = None
    title: Optional[str] = None
    author: Optional[str] = None
    isbn: Optional[str] = None

@app.post("/advanced-search")
def advanced_search_endpoint(req: AdvancedSearchRequest):
    try:
        from db import advanced_search
        books = advanced_search(req.acc_no, req.title, req.author, req.isbn)
        return books
    except Exception as e:
        print(f"[advanced-search] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health():
    return {"status": "ok"}
