<script>
  import { onMount, onDestroy } from 'svelte';
  import { 
    sendWhatsAppMessage, 
    fetchInstances, 
    createInstance, 
    connectInstance, 
    logoutInstance,
    fetchOverdueBooks,
    getCachedQR
  } from '../lib/api';

  let username = "";
  let password = "";
  let isLoggedIn = false;
  let error = "";

  // WhatsApp Connection State
  let connStatus = "checking"; // checking | login | dashboard
  let qrCode = null;
  let pairingCode = null;
  let phoneNumber = "";
  let isPairingLoading = false;

  // Messaging state
  let recipient = "91";
  let dueDate = "";
  let daysLimit = "7";
  let message = "";
  let infoMsg = "";
  let isSending = false;

  let overdueBooks = [];
  let isLoadingOverdue = false;

  const instanceName = "halo";
  let pollInterval;
  let isPolling = false;

  async function checkSetup() {
    try {
      const raw = await fetchInstances();
      const instances = Array.isArray(raw) ? raw : raw?.instances ?? [];
      const halo = instances.find((i) => i.name === instanceName);
      
      if (halo) {
        if (halo.connectionStatus === "open") {
          connStatus = "dashboard";
        } else {
          connStatus = "login";
        }
      } else {
        console.log("[admin] 'halo' instance not found, creating...");
        await createInstance(instanceName);
        connStatus = "login";
      }
    } catch (e) {
      console.error("[admin] checkSetup error:", e);
      error = "WhatsApp API sync failed: " + e.message;
      connStatus = "login";
    }
  }

  async function fetchConnData(num = null) {
    if (num) {
      isPairingLoading = true;
      try { await logoutInstance(instanceName); } catch(e) {}
      await new Promise(r => setTimeout(r, 1000));
    }

    try {
      console.log("[admin] Fetching connection data (QR/Pairing)...");

      // NEW: Try cached QR first for instant ready state
      if (!num) {
        const cached = await getCachedQR();
        if (cached && (cached.code || cached.base64)) {
          console.log("[admin] Using cached QR from backend");
          if (cached.base64) {
            qrCode = cached.base64.startsWith("data:") ? cached.base64 : `data:image/png;base64,${cached.base64}`;
          } else if (cached.code) {
             try {
                const QRCode = (await import("qrcode")).default;
                qrCode = await QRCode.toDataURL(cached.code, { margin: 2, width: 280, errorCorrectionLevel: "M" });
             } catch (e) {
                console.error("[admin] client-side QR render failed (cached):", e);
             }
          }
          if (qrCode) return; // Exit early if we got a good cached QR
        }
      }

      const res = await connectInstance(instanceName, num);

      if (res?.error) {
        console.error("[admin] connect API error:", res.message);
        return;
      }

      // Evolution may return the QR payload at top level, under `qrcode`, or under `data`
      const qrData = res?.qrcode ?? res?.data?.qrcode ?? res;

      let imgSrc = null;
      if (qrData?.base64) {
        imgSrc = qrData.base64.startsWith("data:")
          ? qrData.base64
          : `data:image/png;base64,${qrData.base64}`;
      } else if (qrData?.code && typeof qrData.code === "string") {
        // Baileys often exposes raw QR text before async base64 is ready on the server
        try {
          const QRCode = (await import("qrcode")).default;
          imgSrc = await QRCode.toDataURL(qrData.code, {
            margin: 2,
            width: 280,
            errorCorrectionLevel: "M",
          });
        } catch (e) {
          console.error("[admin] client-side QR render failed:", e);
        }
      }

      if (imgSrc) {
        qrCode = imgSrc;
        console.log("[admin] QR Code received");
      }
      if (qrData?.pairingCode) {
        pairingCode = qrData.pairingCode;
        console.log("[admin] Pairing Code received:", pairingCode);
      }
    } catch (e) {
      console.error("[admin] fetchConnData error:", e);
    }
    isPairingLoading = false;
  }

  function handleLogin() {
    if (username === "hisernbug" && password === "pounds") {
      isLoggedIn = true;
      error = "";
      startPolling();
    } else {
      error = "Invalid username or password";
    }
  }

  async function runPoll() {
    if (isPolling) return;
    isPolling = true;
    try {
      await checkSetup();
      if (connStatus === "login" && !isPairingLoading) {
        await fetchConnData();
      }
    } finally {
      isPolling = false;
    }
  }

  async function forceReset() {
    if (!confirm("This will disconnect WhatsApp and clear the session. Continue?")) return;
    try {
        connStatus = "checking";
        await logoutInstance(instanceName);
        qrCode = null;
        pairingCode = null;
        infoMsg = "Instance reset successfully. Generating new QR...";
        setTimeout(runPoll, 2000);
    } catch (e) {
        error = "Reset failed: " + e.message;
        connStatus = "login";
    }
  }

  function startPolling() {
    void runPoll();
    // Slightly faster while linking WhatsApp so QR appears soon after the server generates it
    pollInterval = setInterval(runPoll, 3000);
  }

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
  });

  function handleLogout() {
    isLoggedIn = false;
    username = "";
    password = "";
    if (pollInterval) clearInterval(pollInterval);
  }

  async function sendMessage() {
    if (recipient.length < 10 || !message) {
      infoMsg = "⚠️ Please enter a valid number and message.";
      return;
    }

    isSending = true;
    infoMsg = "🤫 Sending secure message (anti-ban active)...";
    
    let fullMessage = message;
    if (dueDate) {
      fullMessage += `\n\n📅 Due Date: ${dueDate}\n⏳ Days Limit: ${daysLimit}`;
    }

    try {
      const res = await sendWhatsAppMessage(recipient, fullMessage);
      if (res.status === "success") {
        infoMsg = "✅ " + res.message;
        message = "";
      } else {
        infoMsg = "❌ " + res.message;
      }
    } catch (e) {
      infoMsg = "❌ Error: " + e.message;
    } finally {
      isSending = false;
    }
  }

  async function fetchOverdue() {
    isLoadingOverdue = true;
    try {
      overdueBooks = await fetchOverdueBooks();
    } catch (e) {
      infoMsg = "❌ Error fetching overdue: " + e.message;
    } finally {
      isLoadingOverdue = false;
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
    {#if connStatus === "checking"}
      <div class="dashboard-card" style="text-align: center;">
        <h2>Synchronizing...</h2>
        <p class="info-msg">Establishing connection with Evolution API</p>
      </div>
    {:else if connStatus === "login"}
      <div class="dashboard-card" style="max-width: 800px;">
        <div class="connection-grid">
          <div class="qr-section">
            <h3>Option 1: Scan QR</h3>
            <div class="qr-box">
              {#if qrCode}
                <img src={qrCode} alt="WhatsApp QR Code" />
              {:else}
                <p>Generating QR Code...</p>
              {/if}
            </div>
            <p class="hint">Open WhatsApp > Linked Devices > Link a Device</p>
          </div>

          <div class="pairing-section">
            <h3>Option 2: Pairing Code</h3>
            <div class="input-group">
              <label for="phone">Phone Number</label>
              <input id="phone" type="text" bind:value={phoneNumber} placeholder="91XXXXXXXXXX" />
            </div>
            <button class="login-btn" disabled={isPairingLoading} on:click={() => fetchConnData(phoneNumber)}>
              {isPairingLoading ? 'Requesting...' : 'Get Pairing Code'}
            </button>

            {#if pairingCode}
              <div class="pairing-result">
                <span class="code-label">Your Code</span>
                <div class="code-value">{pairingCode}</div>
              </div>
            {/if}
          </div>
        </div>
        <div style="text-align: center; margin-top: 2rem; border-top: 1px solid var(--border); padding-top: 1rem; display: flex; justify-content: center; gap: 1rem;">
          <button class="secondary-btn" on:click={checkSetup}>Refresh Status</button>
          <button class="secondary-btn" style="color: #ef4444; border-color: rgba(239, 68, 68, 0.3);" on:click={forceReset}>Force Reset Instance</button>
        </div>
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

          <a href="/whatsapp" target="_blank" class="secondary-btn">
            Launch WhatsApp Manager 🚀
          </a>
        </div>

        {#if infoMsg}
          <p class="info-msg">{infoMsg}</p>
        {/if}

        <div class="overdue-section" style="margin-top: 3rem; border-top: 1px solid var(--border); padding-top: 2rem;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
            <h3>Overdue Students Tracking</h3>
            <button class="secondary-btn" style="padding: 0.5rem 1rem;" on:click={fetchOverdue} disabled={isLoadingOverdue}>
              {isLoadingOverdue ? 'Loading...' : 'Refresh List'}
            </button>
          </div>

          <div style="overflow-x: auto;">
            <table style="width: 100%; border-collapse: collapse; font-size: 0.85rem; color: var(--text);">
              <thead>
                <tr style="border-bottom: 1px solid var(--border); text-align: left;">
                  <th style="padding: 0.75rem;">ID NO</th>
                  <th style="padding: 0.75rem;">ACC NO</th>
                  <th style="padding: 0.75rem;">TITLE</th>
                  <th style="padding: 0.75rem;">DUE DATE</th>
                  <th style="padding: 0.75rem;">ACTION</th>
                </tr>
              </thead>
              <tbody>
                {#each overdueBooks as book}
                  <tr style="border-bottom: 1px solid rgba(255,255,255,0.05);">
                    <td style="padding: 0.75rem;">{book.id_no}</td>
                    <td style="padding: 0.75rem;">{book.acc_no}</td>
                    <td style="padding: 0.75rem;">{book.title}</td>
                    <td style="padding: 0.75rem; color: #ef4444;">{book.due_date}</td>
                    <td style="padding: 0.75rem;">
                      <button 
                        class="secondary-btn" 
                        style="padding: 0.3rem 0.6rem; font-size: 0.75rem;"
                        on:click={() => {
                          message = `Reminder: The book '${book.title}' (Acc: ${book.acc_no}) was due on ${book.due_date}. Please return it to the library.`;
                          dueDate = book.due_date;
                        }}
                      >
                        Notify
                      </button>
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
        </div>

    {/if}
  {/if}
</div>

<style>
  .connection-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 3rem;
  }
  .qr-box {
    background: white;
    padding: 1rem;
    border-radius: 12px;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 250px;
  }
  .qr-box img {
    max-width: 230px;
    width: 100%;
  }
  .qr-section h3, .pairing-section h3 {
    color: var(--accent);
    margin-bottom: 1.5rem;
    font-family: 'DM Serif Display', serif;
  }
  .pairing-section {
    border-left: 1px solid var(--border);
    padding-left: 2rem;
  }
  .pairing-result {
    margin-top: 2rem;
    padding: 1.5rem;
    background: rgba(200, 169, 110, 0.1);
    border: 2px dashed var(--accent);
    border-radius: 12px;
    text-align: center;
  }
  .code-label {
    font-size: 0.7rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
  .code-value {
    font-family: monospace;
    font-size: 2.2rem;
    color: var(--accent);
    letter-spacing: 6px;
    margin-top: 0.5rem;
  }
  .hint {
    font-size: 0.8rem;
    color: var(--muted);
    margin-top: 1rem;
  }
  @media (max-width: 768px) {
    .pairing-section {
      border-left: none;
      border-top: 1px solid var(--border);
      padding-left: 0;
      padding-top: 2rem;
    }
  }
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
