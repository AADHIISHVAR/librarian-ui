<script>
  import { onMount } from 'svelte';

  let opened = false;
  let days = 0;
  let hours = 0;
  let minutes = 0;
  let flashActive = false;

  onMount(() => {
    const timer = setTimeout(() => {
      opened = true;
    }, 800);
    return () => clearTimeout(timer);
  });

  function increment(type) {
    if (type === 'days') days = (days + 1) % 100;
    if (type === 'hours') hours = (hours + 1) % 24;
    if (type === 'minutes') minutes = (minutes + 1) % 60;
  }

  function triggerFlash() {
    // 1. Play Sound
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (AudioContext) {
      const ctx = new AudioContext();
      const now = ctx.currentTime;
      
      // --- The "Snap/Pop" ---
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(1200, now);
      osc.frequency.exponentialRampToValueAtTime(40, now + 0.15);
      
      gain.gain.setValueAtTime(0.8, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.15);
      
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(now + 0.15);

      // --- The "High Frequency Whistle" (Recharge) ---
      const osc2 = ctx.createOscillator();
      const gain2 = ctx.createGain();
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(100, now + 0.05);
      osc2.frequency.exponentialRampToValueAtTime(15000, now + 1.5);
      
      gain2.gain.setValueAtTime(0, now + 0.05);
      gain2.gain.linearRampToValueAtTime(0.1, now + 0.1);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 1.5);
      
      osc2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.start();
      osc2.stop(now + 1.5);
    }

    // 2. Visual Flash Logic
    flashActive = true;
    // Keep it fully white for 100ms, then let the CSS transition fade it out
    setTimeout(() => {
      flashActive = false;
    }, 150);
  }

  function format(val) {
    return val.toString().padStart(2, '0');
  }
</script>

<!-- Flash overlay remains in DOM for smooth transition -->
<div class="flash-overlay" class:active={flashActive}></div>

<div class="neuralyzer-container {opened ? 'opened' : ''}">
  <div class="top-part chrome">
    <!-- svelte-ignore a11y-click-events-have-key-events -->
    <!-- svelte-ignore a11y-no-static-element-interactions -->
    <div class="dome" on:click={triggerFlash}></div>
    
    <!-- svelte-ignore a11y-click-events-have-key-events -->
    <!-- svelte-ignore a11y-no-static-element-interactions -->
    <div class="red-button" on:click={triggerFlash} title="Flash"></div>
    
    <div class="dials">
      <div class="dial-row">
        <div class="dial-label">Days</div>
        <div class="dial" on:click={() => increment('days')}>{format(days)}</div>
      </div>
      <div class="dial-row">
        <div class="dial-label">Hours</div>
        <div class="dial" on:click={() => increment('hours')}>{format(hours)}</div>
      </div>
      <div class="dial-row">
        <div class="dial-label">Mins</div>
        <div class="dial" on:click={() => increment('minutes')}>{format(minutes)}</div>
      </div>
    </div>
  </div>
  <div class="base chrome"></div>
  <div class="instruction">
    Set duration · Stand clear · Press red button
  </div>
</div>

<style>
  .flash-overlay {
    position: fixed;
    top: 0; left: 0; 
    width: 100vw; height: 100vh;
    background-color: #ffffff;
    z-index: 999999; /* Absolute max priority */
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.8s ease-out; /* Smooth fade away */
  }

  .flash-overlay.active {
    opacity: 1;
    transition: none; /* Sharp instant white */
  }

  .neuralyzer-container {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    height: 380px; 
    justify-content: flex-end;
    margin: 120px auto 0;
    max-width: 400px;
    z-index: 100;
  }

  .chrome {
    background: linear-gradient(
      90deg,
      #1a1a1a 0%,
      #333 15%,
      #666 30%,
      #999 48%,
      #ccc 50%,
      #999 52%,
      #666 70%,
      #333 85%,
      #1a1a1a 100%
    );
    box-shadow: inset -5px 0 15px rgba(0,0,0,0.6), inset 5px 0 15px rgba(0,0,0,0.6);
  }

  .base {
    width: 60px;
    height: 180px;
    border-radius: 0 0 30px 30px;
    position: relative;
    z-index: 30;
    display: flex;
    justify-content: center;
    border-top: 2px solid #444;
  }

  .base::after {
    content: "";
    position: absolute;
    top: 20px;
    width: 100%;
    height: 110px;
    background: repeating-linear-gradient(
      90deg,
      transparent,
      transparent 4px,
      rgba(0,0,0,0.3) 4px,
      rgba(0,0,0,0.3) 6px
    );
  }

  .top-part {
    width: 52px;
    height: 320px;
    border-radius: 26px 26px 0 0;
    position: absolute;
    bottom: 0;
    z-index: 10;
    transition: transform 0.8s cubic-bezier(0.175, 0.885, 0.32, 1.275);
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-top: 15px;
    box-sizing: border-box;
  }

  .opened .top-part {
    transform: translateY(-160px); 
  }

  .dome {
    width: 40px;
    height: 30px;
    background: radial-gradient(circle at 50% 30%, #ff7777, #aa0000);
    border-radius: 20px 20px 5px 5px;
    border: 2px solid #222;
    box-shadow: 0 0 15px rgba(255,0,0,0.8);
    margin-bottom: 10px;
    position: relative;
    overflow: hidden;
    cursor: pointer;
  }

  .dials {
    display: flex;
    flex-direction: column;
    gap: 12px;
    background: rgba(0,0,0,0.8);
    padding: 10px 6px;
    border-radius: 10px;
    border: 1px solid rgba(255,255,255,0.1);
    margin-top: 10px;
  }

  .dial-row {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
  }

  .dial-label {
    font-size: 7px;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .dial {
    width: 28px;
    height: 18px;
    background: #000;
    border: 1px solid #333;
    color: #ff3333;
    display: flex;
    justify-content: center;
    align-items: center;
    font-family: 'Courier New', Courier, monospace;
    font-size: 11px;
    font-weight: bold;
    cursor: pointer;
    user-select: none;
    border-radius: 2px;
    box-shadow: inset 0 0 3px rgba(255,0,0,0.5);
  }

  .red-button {
    width: 24px;
    height: 24px;
    background: radial-gradient(circle at 30% 30%, #ff5555, #880000);
    border-radius: 50%;
    cursor: pointer;
    border: 2px solid #222;
    box-shadow: 0 0 12px rgba(255,0,0,0.5);
    transition: transform 0.1s;
    z-index: 100;
  }

  .red-button:active {
    transform: scale(0.9);
  }

  .instruction {
    position: absolute;
    bottom: -60px;
    width: 100%;
    font-size: 10px;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 1px;
    opacity: 0;
    transition: opacity 1s;
    text-align: center;
  }

  .opened .instruction {
    opacity: 1;
  }
</style>
