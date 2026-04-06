// On Hugging Face, we serve from the same origin. 
// On GitHub Pages, we point to the HF API.
const isGitHubPages = window.location.hostname.includes('github.io');
const BACKEND_URL = isGitHubPages 
  ? "https://aadhiishvar-library-assist-alphav1-10.hf.space" 
  : "";

const LIBRARIAN_KEY = "LIB_AI_2024_SECURE_TOKEN";

export async function search(prompt, library = "all") {
  const res = await fetch(`${BACKEND_URL}/api/search`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify({ prompt, library, top_k: 5 })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function listBooks(library, query = null) {
  const res = await fetch(`${BACKEND_URL}/api/list`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify({ library, query })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}
