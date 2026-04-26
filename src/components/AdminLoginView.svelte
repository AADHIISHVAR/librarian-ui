<script>
  let username = "";
  let password = "";

  function handleLogin() {
    alert("Admin login is not implemented yet.");
  }
</script>

<div class="admin-container">
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
    <button class="login-btn" on:click={handleLogin}>Log In</button>
  </div>
</div>

<style>
  .admin-container {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 50vh;
  }
  .login-card {
    background: var(--card);
    border: 1px solid var(--border);
    padding: 2.5rem;
    border-radius: 16px;
    width: 100%;
    max-width: 400px;
    box-shadow: 0 20px 40px rgba(0,0,0,0.4);
  }
  h2 {
    font-family: 'DM Serif Display', serif;
    margin-bottom: 2rem;
    text-align: center;
    color: var(--accent);
  }
  .input-group {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
  }
  label {
    font-size: 0.8rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  input {
    background: rgba(0,0,0,0.2);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.8rem 1rem;
    color: var(--text);
    outline: none;
    transition: all 0.2s;
  }
  input:focus {
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
  .login-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(200, 169, 110, 0.3);
  }
</style>
