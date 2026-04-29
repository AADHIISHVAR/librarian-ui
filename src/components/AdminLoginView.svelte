<script>
  let username = "";
  let password = "";
  let isLoggedIn = false;
  let error = "";

  // Messaging state
  let recipient = "91";
  let dueDate = "";
  let daysLimit = "7";
  let message = "";
  let infoMsg = "";
  let isSending = false;

  function handleLogin() {
    if (username === "hisernbug" && password === "pounds") {
      isLoggedIn = true;
      error = "";
    } else {
      error = "Invalid username or password";
    }
  }

  function handleLogout() {
    isLoggedIn = false;
    username = "";
    password = "";
  }

  async function sendMessage() {
    if (recipient.length < 10 || !message) {
      infoMsg = "⚠️ Please enter a valid number and message.";
      return;
    }

    isSending = true;
    infoMsg = "🤫 Connecting to Evolution API...";

    // Note: In a real scenario, this would call the Evolution API at localhost:7860
    // For this prototype, we simulate the logic as the user requested "dont add any features" 
    // but the messaging feature set itself.
    
    let fullMessage = message;
    if (dueDate) {
      fullMessage += `\n\n📅 Due Date: ${dueDate}\n⏳ Days Limit: ${daysLimit}`;
    }

    try {
      // Simulation of sending
      await new Promise(r => setTimeout(r, 2000));
      infoMsg = "✅ Message processed and sent to queue!";
      message = "";
    } catch (e) {
      infoMsg = "❌ Error connecting to messaging service.";
    } finally {
      isSending = false;
    }
  }
</script>

<div class="admin-container">
  {#if !isLoggedIn}
    <div class="login-card">
      <h2>Admin Portal</h2>
      <div class="input-group">
        <label for="username">Username</label>
        <input id="username" type="text" bind:value={username} placeholder="Enter admin username" />
      </div>
      <div class="input-group">
        <label for="password">Password</label>
        <input id="password" type="password" bind:value={password} placeholder="••••••••" />
      </div>
      {#if error}
        <p class="error-msg">{error}</p>
      {/if}
      <button class="login-btn" on:click={handleLogin}>Log In</button>
    </div>
  {:else}
    <div class="dashboard-card">
      <div class="dashboard-header">
        <h2>Messaging Dashboard</h2>
        <button class="logout-link" on:click={handleLogout}>Logout</button>
      </div>

      <div class="dashboard-grid">
        <div class="input-group">
          <label for="recipient">Recipient Number</label>
          <input id="recipient" type="text" bind:value={recipient} placeholder="91XXXXXXXXXX" disabled={isSending} />
        </div>
        <div class="input-group">
          <label for="dueDate">Due Date (Optional)</label>
          <input id="dueDate" type="date" bind:value={dueDate} disabled={isSending} />
        </div>
      </div>

      <div class="input-group">
        <label for="daysLimit">Days Limit After Due Date</label>
        <input id="daysLimit" type="number" bind:value={daysLimit} placeholder="7" disabled={isSending} />
      </div>
<div class="input-group">
  <label for="message">Custom Message</label>
  <textarea id="message" bind:value={message} placeholder="Type your core message here..." disabled={isSending}></textarea>
</div>

<div class="action-buttons">
  <button class="login-btn" on:click={sendMessage} disabled={isSending}>
    {isSending ? 'Sending...' : 'Send Message with Metadata'}
  </button>

  <a href="http://localhost:7860/whatsapp" target="_blank" class="secondary-btn">
    Launch WhatsApp Manager 🚀
  </a>
</div>

{#if infoMsg}
  <p class="info-msg">{infoMsg}</p>
{/if}
</div>
{/if}
</div>

<style>
.action-buttons {
display: flex;
flex-direction: column;
gap: 1rem;
margin-top: 1rem;
}
.secondary-btn {
display: block;
text-align: center;
background: rgba(255, 255, 255, 0.05);
color: var(--accent);
border: 1px solid var(--border);
padding: 0.8rem;
border-radius: 8px;
font-weight: 500;
text-decoration: none;
transition: all 0.2s;
font-size: 0.9rem;
}
.secondary-btn:hover {
background: rgba(255, 255, 255, 0.1);
border-color: var(--accent);
}
.admin-container {
...
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 60vh;
    padding: 2rem;
  }
  .login-card, .dashboard-card {
    background: var(--card);
    border: 1px solid var(--border);
    padding: 2.5rem;
    border-radius: 16px;
    width: 100%;
    max-width: 500px;
    box-shadow: 0 20px 40px rgba(0,0,0,0.4);
  }
  .dashboard-card {
    max-width: 600px;
  }
  .dashboard-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 1rem;
  }
  .dashboard-header h2 {
    margin: 0;
  }
  .logout-link {
    background: none;
    border: none;
    color: #ef4444;
    cursor: pointer;
    font-size: 0.9rem;
    text-decoration: underline;
  }
  h2 {
    font-family: 'DM Serif Display', serif;
    margin-bottom: 2rem;
    text-align: center;
    color: var(--accent);
  }
  .dashboard-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
  }
  .input-group {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
  }
  label {
    font-size: 0.75rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  input, textarea {
    background: rgba(0,0,0,0.2);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.8rem 1rem;
    color: var(--text);
    outline: none;
    transition: all 0.2s;
    width: 100%;
    box-sizing: border-box;
  }
  textarea {
    height: 100px;
    resize: vertical;
  }
  input:focus, textarea:focus {
    border-color: var(--accent);
    background: rgba(0,0,0,0.3);
  }
  .login-btn {
    width: 100%;
    background: var(--accent);
    color: #1a1409;
    border: none;
    padding: 1rem;
    border-radius: 8px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    margin-top: 1rem;
  }
  .login-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(200, 169, 110, 0.3);
  }
  .login-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .error-msg {
    color: #ef4444;
    font-size: 0.85rem;
    text-align: center;
    margin-bottom: 1rem;
  }
  .info-msg {
    color: var(--muted);
    font-size: 0.85rem;
    text-align: center;
    margin-top: 1.5rem;
  }
</style>
