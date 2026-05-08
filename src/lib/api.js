// On Hugging Face, we serve from the same origin. 
// On GitHub Pages, we point to the HF API.
const isGitHubPages = window.location.hostname.includes('github.io');
const BACKEND_URL = isGitHubPages 
  ? "https://butler-columnists-christopher-fantasy.trycloudflare.com" 
  : "";
 
const LIBRARIAN_KEY = "hellowork.1234";


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

export async function sendWhatsAppMessage(instance, number, text) {
  const res = await fetch(`${BACKEND_URL}/api/whatsapp/send`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LIBRARIAN_KEY}`,
      'x-librarian-key': LIBRARIAN_KEY
    },
    body: JSON.stringify({ instance, number, text })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchInstances() {
  const res = await fetch(`${BACKEND_URL}/instance/fetchInstances`, {
    headers: { 'apikey': LIBRARIAN_KEY }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function createInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/create`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'apikey': LIBRARIAN_KEY
    },
    body: JSON.stringify({ 
      instanceName: name, 
      token: Math.random().toString(36).substring(2, 15),
      qrcode: true,
      integration: 'WHATSAPP-BAILEYS'
    })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function requestPairingCode(name, number) {
  // Try the most likely endpoints for the latest Evolution API versions
  const endpoints = [
    `${BACKEND_URL}/instance/connect/${name}/pairingCode`,
    `${BACKEND_URL}/instance/connect/${name}/pairing_code`,
    `${BACKEND_URL}/instance/pairingcode/${name}`,
  ];

  for (const url of endpoints) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'apikey': LIBRARIAN_KEY
        },
        body: JSON.stringify({ phoneNumber: number })
      });
      if (res.ok) {
        return await res.json();
      }
    } catch (e) {
      console.log(`[api] Trying endpoint ${url} failed...`);
    }
  }
  throw new Error("Pairing code endpoint not found on this API version");
}

export async function connectInstance(name, number = null) {
  let url = `${BACKEND_URL}/instance/connect/${name}`;
  if (number) url += `?number=${number}`;
  
  const res = await fetch(url, {
    headers: { 'apikey': LIBRARIAN_KEY }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function logoutInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/logout/${name}`, {
    method: 'DELETE',
    headers: { 'apikey': LIBRARIAN_KEY }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function deleteInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/delete/${name}`, {
    method: 'DELETE',
    headers: { 'apikey': LIBRARIAN_KEY }
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

export async function getCachedQR(instanceName) {
  try {
    const res = await fetch(`${BACKEND_URL}/api/whatsapp/qr`);
    if (!res.ok) return null;
    const data = await res.json();
    
    // Only return the cache if it belongs to the requested instance
    if (data?.instance === instanceName) {
      return data;
    }
    return null;
  } catch (e) {
    console.error("[api] getCachedQR error:", e);
    return null;
  }
}

