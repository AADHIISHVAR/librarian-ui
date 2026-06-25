<script>
  import { onMount } from 'svelte';

  let users = [];
  let loading = true;

  onMount(async () => {
    let usernames = ["AADHIISHVAR"];
    try {
      const settingsRes = await fetch("/api/settings/developer_username");
      if (settingsRes.ok) {
        const settingsData = await settingsRes.json();
        if (settingsData && settingsData.value) {
          usernames = settingsData.value.split(",").map(u => u.trim()).filter(Boolean);
        }
      }
    } catch (e) {
      console.warn("Failed to fetch settings, using default AADHIISHVAR:", e);
    }

    const fetchedUsers = [];
    for (const username of usernames) {
      try {
        const res = await fetch(`https://api.github.com/users/${username}`);
        if (!res.ok) {
          throw new Error(`GitHub API returned status: ${res.status}`);
        }
        const data = await res.json();
        fetchedUsers.push(data);
      } catch (e) {
        console.warn(`GitHub API error for ${username}, using fallback data:`, e);
        fetchedUsers.push({
          login: username,
          name: username,
          avatar_url: `https://github.com/${username}.png?size=250`,
          bio: "Contributor & Maintainer of Librarian UI",
          location: "",
          public_repos: 0,
          followers: 0,
          html_url: `https://github.com/${username}`
        });
      }
    }
    users = fetchedUsers;
    loading = false;
  });

  const contributions = [
    {
      icon: "🎨",
      title: "UI & Frontend Heuristics",
      desc: "Love Svelte & CSS? Help us add animations, light/dark themes, or clean up layouts."
    },
    {
      icon: "🤖",
      title: "AI & Vector Search Heuristics",
      desc: "Help us optimize embeddings, HyDE contexts, and similarity thresholds in Rust & Python."
    },
    {
      icon: "⚡",
      title: "Rust & API Optimization",
      desc: "Help optimize database queries, Evolution API endpoints, and connection queues."
    },
    {
      icon: "📦",
      title: "Seeding & Data Scraping",
      desc: "Integrate more department catalogs, automate title mapping, or write seeders."
    }
  ];
</script>

<div class="about-container">
  <div class="about-hero">
    <h1>About <em>Librarian</em></h1>
    <p>A smart library assistant built by students, for students.</p>
  </div>

  <div class="about-grid">
    <!-- Creator Profile Card -->
    <div class="about-card profile-card">
      <h2 class="card-section-title">Developers & Contributors</h2>
      {#if loading}
        <div class="card-loading">
          <div class="spinner-small"></div>
          <span>Fetching profiles...</span>
        </div>
      {:else}
        <div class="users-list-layout" style="display: flex; flex-direction: column; gap: 2rem;">
          {#each users as userData, idx}
            <div class="profile-layout" style="border-bottom: {idx === users.length - 1 ? 'none' : '1px solid var(--border)'}; padding-bottom: {idx === users.length - 1 ? '0' : '1.5rem'}; margin-bottom: {idx === users.length - 1 ? '0' : '0.5rem'};">
              <div class="avatar-wrap">
                <img src={userData.avatar_url} alt="{userData.name || userData.login}'s avatar" class="avatar-img" />
                <div class="avatar-glow"></div>
              </div>
              
              <div class="profile-info">
                <div class="profile-name">{userData.name || userData.login}</div>
                <div class="profile-username">@{userData.login}</div>
                <div class="profile-bio">{userData.bio || "Full stack developer crafting automation tools."}</div>
                {#if userData.location}
                  <div class="profile-meta">
                    <span class="meta-icon">📍</span> {userData.location}
                  </div>
                {/if}
                
                <div class="github-stats">
                  <div class="stat-box">
                    <span class="stat-val">{userData.public_repos}</span>
                    <span class="stat-lbl">Repos</span>
                  </div>
                  <div class="stat-box">
                    <span class="stat-val">{userData.followers}</span>
                    <span class="stat-lbl">Followers</span>
                  </div>
                </div>

                <a href={userData.html_url} target="_blank" rel="noopener noreferrer" class="github-btn">
                  <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" class="btn-svg">
                    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                  </svg>
                  Follow on GitHub
                </a>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Contribute Call to Action Card -->
    <div class="about-card cta-card">
      <h2 class="card-section-title">Join the Build 🛠️</h2>
      <p class="cta-text">
        Librarian was started as a solo project to solve a very simple frustration: finding books in the college catalog quickly and getting reminders for overdue books.
      </p>
      <p class="cta-text">
        But building software alone can be tough. We want this to be a platform where fellow engineering students can collaborate, experiment with AI embeddings, write APIs, optimize queries, and deploy production apps.
      </p>
      
      <div class="contrib-grid">
        {#each contributions as item}
          <div class="contrib-item">
            <span class="contrib-icon">{item.icon}</span>
            <div class="contrib-info">
              <div class="contrib-title">{item.title}</div>
              <div class="contrib-desc">{item.desc}</div>
            </div>
          </div>
        {/each}
      </div>

      <div class="cta-actions">
        <a href="https://github.com/AADHIISHVAR/librarian-ui" target="_blank" rel="noopener noreferrer" class="primary-btn">
          ✨ Fork & Contribute on GitHub
        </a>
      </div>
    </div>
  </div>
</div>

<style>
  .about-container {
    max-width: 950px;
    margin: 1.5rem auto 3rem auto;
    padding: 0 1rem;
    animation: fadeIn 0.4s ease-out;
  }

  .about-hero {
    text-align: center;
    margin-bottom: 2.5rem;
  }

  .about-hero h1 {
    font-family: 'DM Serif Display', serif;
    font-size: 2.2rem;
    color: var(--text);
  }

  .about-hero h1 em {
    font-style: italic;
    color: var(--accent);
  }

  .about-hero p {
    font-size: 0.95rem;
    color: var(--muted);
    margin-top: 0.5rem;
  }

  .about-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: 1.5rem;
  }

  @media (min-width: 768px) {
    .about-grid {
      grid-template-columns: 1.2fr 1.8fr;
    }
  }

  .about-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    position: relative;
    overflow: hidden;
    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.2);
  }

  .card-section-title {
    font-family: 'DM Serif Display', serif;
    font-size: 1.3rem;
    color: var(--accent);
    margin-bottom: 1.2rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.6rem;
  }

  /* Profile Card Styles */
  .profile-layout {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1.5rem;
    text-align: center;
  }

  .avatar-wrap {
    position: relative;
    width: 140px;
    height: 140px;
  }

  .avatar-img {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    object-fit: cover;
    border: 2px solid var(--accent);
    z-index: 2;
    position: relative;
  }

  .avatar-glow {
    position: absolute;
    top: 50%;
    left: 50%;
    width: 120px;
    height: 120px;
    background: var(--accent);
    filter: blur(25px);
    opacity: 0.25;
    border-radius: 50%;
    transform: translate(-50%, -50%);
    z-index: 1;
    pointer-events: none;
  }

  .profile-info {
    width: 100%;
  }

  .profile-name {
    font-size: 1.25rem;
    font-weight: 500;
    color: var(--text);
  }

  .profile-username {
    font-family: 'DM Mono', monospace;
    font-size: 0.8rem;
    color: var(--accent2);
    margin-top: 0.2rem;
  }

  .profile-bio {
    font-size: 0.85rem;
    color: var(--text);
    opacity: 0.85;
    margin-top: 0.8rem;
    line-height: 1.4;
  }

  .profile-meta {
    font-size: 0.8rem;
    color: var(--muted);
    margin-top: 0.6rem;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.3rem;
  }

  .github-stats {
    display: flex;
    justify-content: center;
    gap: 1.5rem;
    margin: 1.2rem 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.6rem;
  }

  .stat-box {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .stat-val {
    font-size: 1.1rem;
    font-weight: 500;
    color: var(--text);
  }

  .stat-lbl {
    font-size: 0.65rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-top: 0.1rem;
  }

  .github-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.65rem;
    background: transparent;
    border: 1px solid var(--accent);
    color: var(--accent);
    border-radius: 6px;
    font-size: 0.85rem;
    text-decoration: none;
    transition: all 0.2s ease;
    cursor: pointer;
  }

  .github-btn:hover {
    background: var(--accent);
    color: #1a1409;
    box-shadow: 0 4px 12px rgba(200, 169, 110, 0.15);
  }

  .btn-svg {
    flex-shrink: 0;
  }

  /* Loading State */
  .card-loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.8rem;
    padding: 3rem 0;
    color: var(--muted);
    font-size: 0.85rem;
  }

  .spinner-small {
    width: 24px;
    height: 24px;
    border: 2px solid var(--border);
    border-top: 2px solid var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  /* CTA Card Styles */
  .cta-text {
    font-size: 0.88rem;
    line-height: 1.5;
    color: var(--text);
    opacity: 0.9;
    margin-bottom: 0.8rem;
  }

  .contrib-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: 1rem;
    margin: 1.5rem 0;
  }

  @media (min-width: 480px) {
    .contrib-grid {
      grid-template-columns: 1fr 1fr;
    }
  }

  .contrib-item {
    display: flex;
    gap: 0.8rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.8rem;
    transition: border-color 0.2s ease, transform 0.2s ease;
  }

  .contrib-item:hover {
    border-color: var(--accent2);
    transform: translateY(-2px);
  }

  .contrib-icon {
    font-size: 1.25rem;
    flex-shrink: 0;
  }

  .contrib-info {
    display: flex;
    flex-direction: column;
  }

  .contrib-title {
    font-size: 0.8rem;
    font-weight: 500;
    color: var(--text);
  }

  .contrib-desc {
    font-size: 0.72rem;
    color: var(--muted);
    margin-top: 0.2rem;
    line-height: 1.35;
  }

  .cta-actions {
    margin-top: 1.5rem;
    text-align: center;
  }

  .primary-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.8rem 1.5rem;
    background: var(--accent);
    border: none;
    color: #1a1409;
    font-weight: bold;
    border-radius: 6px;
    font-size: 0.9rem;
    text-decoration: none;
    transition: all 0.2s ease;
    cursor: pointer;
    box-shadow: 0 4px 15px rgba(200, 169, 110, 0.2);
  }

  .primary-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(200, 169, 110, 0.3);
    filter: brightness(1.05);
  }

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>
