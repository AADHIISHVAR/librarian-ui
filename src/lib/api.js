// On GitHub Pages, we point to the main Rust backend (Azure VM via Cloudflare)
const isGitHubPages = window.location.hostname.includes('github.io');

const BACKEND_URL = isGitHubPages 
  ? "https://butler-columnists-christopher-fantasy.trycloudflare.com" 
  : "";

const LIBRARIAN_KEY = "hellowork.1234";
let currentToken = localStorage.getItem("librarian_token") || LIBRARIAN_KEY;

export function setToken(token) {
  currentToken = token;
  localStorage.setItem("librarian_token", token);
}

export function clearToken() {
  currentToken = LIBRARIAN_KEY;
  localStorage.removeItem("librarian_token");
}

export function getToken() {
  return currentToken;
}

export async function login(username, password) {
  const res = await fetch(`${BACKEND_URL}/api/admin/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ username, password })
  });
  if (!res.ok) {
    if (res.status === 401) {
      throw new Error("Invalid username or password");
    }
    throw new Error(`Server error: ${res.status}`);
  }
  const data = await res.json();
  if (data && data.token) {
    setToken(data.token);
  }
  return data;
}

export async function search(prompt, library = "all") {
  const hfSpaceUrl = window.HF_SPACE_URL || "https://aadhiishvar-enriched-ai.hf.space";
  
  try {
    // 1. Call the Hugging Face Space search API directly
    const hfRes = await fetch(`${hfSpaceUrl}/search`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ prompt, limit: 10 })
    });
    
    if (!hfRes.ok) {
      throw new Error(`Hugging Face Space returned status ${hfRes.status}`);
    }
    
    const { acc_nos, similarities } = await hfRes.json();
    if (!acc_nos || acc_nos.length === 0) {
      return { books: [], reply: "No matching books found." };
    }
    
    // 2. Fetch full book details (including cover URLs & AI descriptions) from backend
    const res = await fetch(`${BACKEND_URL}/api/books/batch`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${currentToken}`,
        'x-librarian-key': currentToken
      },
      body: JSON.stringify({ acc_nos })
    });
    
    if (!res.ok) throw new Error(`Backend resolution error: ${res.status}`);
    const books = await res.json();
    
    // Maintain the order returned by Hugging Face Space and map the similarity
    const orderedBooks = acc_nos.map((accNo, index) => {
      const book = books.find(b => b.accession_num === accNo);
      if (book) {
        return {
          ...book,
          similarity: similarities && similarities[index] !== undefined ? similarities[index] : 1.0
        };
      }
      return null;
    }).filter(Boolean);
    
    return {
      books: orderedBooks,
      reply: `AI Semantic Search resolved ${orderedBooks.length} matches from catalog.`
    };
    
  } catch (error) {
    console.warn("Hugging Face AI search failed, falling back to local backend search:", error);
    
    // Fallback to local Axum search
    const res = await fetch(`${BACKEND_URL}/api/search`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${currentToken}`,
        'x-librarian-key': currentToken
      },
      body: JSON.stringify({ prompt, library, top_k: 5 })
    });
    if (!res.ok) throw new Error(`Local search failed: ${res.status}`);
    return await res.json();
  }
}

export async function listBooks(library, query = null) {
  const res = await fetch(`${BACKEND_URL}/api/list`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
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
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
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
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    },
    body: JSON.stringify({ instance, number, text })
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchInstances() {
  const res = await fetch(`${BACKEND_URL}/instance/fetchInstances`, {
    headers: { 'apikey': currentToken }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function createInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/create`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'apikey': currentToken
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
          'apikey': currentToken
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
    headers: { 'apikey': currentToken }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function logoutInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/logout/${name}`, {
    method: 'DELETE',
    headers: { 'apikey': currentToken }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function deleteInstance(name) {
  const res = await fetch(`${BACKEND_URL}/instance/delete/${name}`, {
    method: 'DELETE',
    headers: { 'apikey': currentToken }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchOverdueBooks() {
  const res = await fetch(`${BACKEND_URL}/api/overdue`, {
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
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

export async function fetchStudentsDueOverview(params = {}) {
  const query = new URLSearchParams();
  if (params.department) query.append('department', params.department);
  if (params.category) query.append('category', params.category);
  if (params.overdue_only) query.append('overdue_only', 'true');
  if (params.limit) query.append('limit', params.limit.toString());
  if (params.offset) query.append('offset', params.offset.toString());
  if (params.class_name) query.append('class_name', params.class_name);
  if (params.search_query) query.append('search_query', params.search_query);
  if (params.study_year) query.append('study_year', params.study_year);
  if (params.gender) query.append('gender', params.gender);
  
  const res = await fetch(`${BACKEND_URL}/api/admin/students-due?${query}`, {
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchFilterOptions() {
  const res = await fetch(`${BACKEND_URL}/api/admin/filter-options`, {
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function markBookReturned(idNo, accNo) {
  const res = await fetch(`${BACKEND_URL}/api/admin/mark-returned/${encodeURIComponent(idNo)}/${accNo}`, {
    method: 'POST',
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function searchMember(params = {}) {
  const query = new URLSearchParams();
  if (params.roll_no) query.append('roll_no', params.roll_no);
  if (params.reg_no) query.append('reg_no', params.reg_no);
  if (params.dept) query.append('dept', params.dept);
  if (params.batch) query.append('batch', params.batch);
  if (params.phone) query.append('phone', params.phone);
  if (params.name) query.append('name', params.name);

  const res = await fetch(`${BACKEND_URL}/api/admin/search-member?${query}`, {
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function fetchDuelistReport(params = {}) {
  const query = new URLSearchParams();
  if (params.department) query.append('department', params.department);
  if (params.category) query.append('category', params.category);
  if (params.class_name) query.append('class_name', params.class_name);
  if (params.study_year) query.append('study_year', params.study_year);
  if (params.gender) query.append('gender', params.gender);
  if (params.id_pattern) query.append('id_pattern', params.id_pattern);
  if (params.match_type) query.append('match_type', params.match_type);
  if (params.active_status) query.append('active_status', params.active_status);
  if (params.fine_rate) query.append('fine_rate', params.fine_rate.toString());

  const res = await fetch(`${BACKEND_URL}/api/admin/reports/duelist?${query}`, {
    headers: { 
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    }
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function addMember(params) {
  const res = await fetch(`${BACKEND_URL}/api/admin/members/add`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    },
    body: JSON.stringify(params)
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}

export async function addBook(params) {
  const res = await fetch(`${BACKEND_URL}/api/admin/books/add`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${currentToken}`,
      'x-librarian-key': currentToken
    },
    body: JSON.stringify(params)
  });
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return await res.json();
}
