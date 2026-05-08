import requests, os, time
from dotenv import load_dotenv

load_dotenv()

HF_TOKEN = os.getenv("HF_TOKEN")
API_URL = "https://router.huggingface.co/v1/chat/completions"
MODEL = "meta-llama/Llama-3.1-8B-Instruct"

SYSTEM_PROMPT = """You are a warm and helpful college library assistant.
You will be given a student's request and a list of books from the library database.

Rules you must strictly follow:
- ONLY recommend books from the list provided. Never invent books.
- ALWAYS mention the exact library name (Central or MBA) and shelf location.
- If the best match is checked out, say so clearly and recommend the next available one.
- Keep your reply to 3 to 5 sentences maximum.
- Be friendly and encouraging — like a knowledgeable librarian who genuinely wants to help."""


def build_user_message(
    user_prompt: str, books: list[dict], hyde_context: str | None = None
) -> str:
    if not books:
        return (
            f'The student asked: "{user_prompt}"\n\n'
            "No matching books were found. "
            "Apologise politely and suggest they try a different search."
        )

    lines = "\n".join(
        [
            f'{i + 1}. "{b["title"]}" by {b["author"]}'
            f" | {b['library']} Library"
            f" | Shelf: {b['shelf']}"
            f" | {'✅ Available' if b['available'] else '❌ Checked out'}"
            f" | Match: {round(b['similarity'] * 100)}%"
            for i, b in enumerate(books)
        ]
    )

    context_info = (
        f"\nRelated topics to consider: {hyde_context}" if hyde_context else ""
    )

    return (
        f'Student request: "{user_prompt}"{context_info}\n\n'
        f"Books found:\n{lines}\n\n"
        "Recommend the best match. Tell them exactly where to find it and why it suits their need."
    )


def generate_response(
    user_prompt: str, books: list[dict], hyde_context: str | None = None
) -> str:
    headers = {"Authorization": f"Bearer {HF_TOKEN}"}
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": build_user_message(user_prompt, books, hyde_context),
            },
        ],
        "max_tokens": 220,
        "temperature": 0.7,
        "top_p": 0.9,
    }

    for attempt in range(3):
        try:
            res = requests.post(API_URL, headers=headers, json=payload, timeout=30)
            if res.status_code == 503:
                wait = res.json().get("estimated_time", 15)
                print(f"[generator] Model loading, waiting {wait:.0f}s...")
                time.sleep(min(wait, 20))
                continue
            if res.status_code == 429:
                time.sleep(10)
                continue
            res.raise_for_status()
            return res.json()["choices"][0]["message"]["content"].strip()

        except requests.exceptions.Timeout:
            if attempt == 2 and books:
                b = books[0]
                return (
                    f'Best match: "{b["title"]}" by {b["author"]} — '
                    f"{b['library']} Library, {b['shelf']}. "
                    f"{'Available now.' if b['available'] else 'Currently checked out.'}"
                )
        except Exception as e:
            print(f"[generator] Attempt {attempt + 1} error: {e}")
            if attempt == 2 and books:
                b = books[0]
                return (
                    f'Best match: "{b["title"]}" by {b["author"]} — '
                    f"{b['library']} Library, {b['shelf']}. "
                    f"{'Available now.' if b['available'] else 'Currently checked out.'}"
                )

    return "Unable to respond right now. Please try again."


def generate_hyde_query(user_prompt: str) -> str:
    """
    Generates a dense, keyword-rich 'ideal' book description based on the prompt.
    Focuses on terms likely found in a library catalog (title, subject, keywords).
    """
    headers = {"Authorization": f"Bearer {HF_TOKEN}"}
    payload = {
        "model": MODEL,
        "messages": [
            {
                "role": "system",
                "content": "You are a specialized library research assistant. For any user query, provide a 2-sentence description of an 'ideal' book on the topic. Use precise academic terminology and include likely keywords or synonyms that would appear in a book title or catalog entry. Do not mention specific titles or authors.",
            },
            {"role": "user", "content": f"Query: {user_prompt}"},
        ],
        "max_tokens": 100,
        "temperature": 0.3,
    }

    try:
        res = requests.post(API_URL, headers=headers, json=payload, timeout=20)
        res.raise_for_status()
        return res.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"[hyde] Error: {e}")
        return user_prompt
