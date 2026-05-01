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
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
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
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify({ library, query })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function advancedSearch(params) {
  const res = await fetch(`${BACKEND_URL}/api/advanced-search`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify(params)
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function sendWhatsAppMessage(number, text) {
  const res = await fetch(`${BACKEND_URL}/api/whatsapp/send`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify({ number, text })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchInstances() {
  const res = await fetch(`${BACKEND_URL}/instance/fetchInstances`, {
    headers: { 'apikey': 'hellowork.1234' }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function createInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/create`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'apikey': 'hellowork.1234'
    },
    body: JSON.stringify({ 
      instanceName: name, 
      qrcode: true,
      integration: 'WHATSAPP-BAILEYS'
    })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function connectInstance(name, number = null) {
  let url = `${BACKEND_URL}/instance/connect/${name}`;
  if (number) url += `?number=${number}`;
  
  const res = await fetch(url, {
    headers: { 'apikey': 'hellowork.1234' }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function logoutInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/logout/${name}`, {
    method: 'DELETE',
    headers: { 'apikey': 'hellowork.1234' }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchOverdueBooks() {
  const res = await fetch(`${BACKEND_URL}/api/overdue`, {
    headers: { 
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
      'x-librarian-key': LIBRARIAN_KEY
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}
