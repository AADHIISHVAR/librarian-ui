<script>
  import { addBook } from '../lib/api';

  let accNo = '';
  let title = '';
  let author = '';
  let edition = '1';
  let pubYear = new Date().getFullYear();
  let price = '';
  let isbn = '';
  let subject = '';
  let location = '';
  let llibNo = 1; // Default Central Library

  let isSubmitting = false;
  let successMessage = '';
  let errorMessage = '';

  async function handleSubmit() {
    if (!accNo || !title.trim() || !author.trim()) {
      errorMessage = 'Accession Number, Book Title, and Author are mandatory fields.';
      return;
    }

    const accessionInt = parseInt(accNo);
    if (isNaN(accessionInt)) {
      errorMessage = 'Accession Number must be a valid integer.';
      return;
    }

    isSubmitting = true;
    errorMessage = '';
    successMessage = '';

    try {
      const payload = {
        acc_no: accessionInt,
        title: title.trim().toUpperCase(),
        author: author.trim().toUpperCase(),
        edition: edition.trim(),
        pub_year: parseInt(pubYear),
        price: parseFloat(price) || 0.0,
        isbn: isbn.trim(),
        subject: subject.trim().toUpperCase(),
        location: location.trim().toUpperCase(),
        llib_no: parseInt(llibNo)
      };

      const result = await addBook(payload);
      if (result.status === 'success') {
        successMessage = `Successfully added book: ${title.toUpperCase()} (Accession No: ${accNo})`;
        // Reset form
        accNo = '';
        title = '';
        author = '';
        price = '';
        isbn = '';
        subject = '';
        location = '';
      } else {
        errorMessage = result.message || 'Failed to add book.';
      }
    } catch (e) {
      console.error(e);
      errorMessage = `Error: ${e.message}`;
    } finally {
      isSubmitting = false;
    }
  }
</script>

<div class="master-search-container animate-fade">
  <div class="glass-card panel-card search-inputs-card" style="width: 100%; max-width: 800px; margin: 0 auto;">
    <div class="panel-header">
      <div class="header-with-icon">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" stroke-width="2">
          <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
          <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
          <line x1="12" y1="6" x2="12" y2="18" />
          <line x1="9" y1="12" x2="15" y2="12" />
        </svg>
        <h3>Add New Book</h3>
      </div>
      <p class="panel-subtitle">Insert a new copy or title record into both catalog indexes and student due registries.</p>
    </div>

    <div class="panel-body">
      {#if successMessage}
        <div class="alert-box alert-success animate-fade">
          <span class="alert-icon">✓</span>
          <span class="alert-text">{successMessage}</span>
        </div>
      {/if}

      {#if errorMessage}
        <div class="alert-box alert-error animate-fade">
          <span class="alert-icon">⚠</span>
          <span class="alert-text">{errorMessage}</span>
        </div>
      {/if}

      <div class="search-inputs-grid" style="grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));">
        <div class="cyber-input-group">
          <label for="b-acc">Accession Number *</label>
          <input id="b-acc" type="number" bind:value={accNo} placeholder="e.g. 36630" required disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-title">Book Title *</label>
          <input id="b-title" type="text" bind:value={title} placeholder="e.g. CLEAN CODE" required disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-author">Author *</label>
          <input id="b-author" type="text" bind:value={author} placeholder="e.g. ROBERT C. MARTIN" required disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-lib">Destination Library</label>
          <select id="b-lib" class="cyber-select" bind:value={llibNo} disabled={isSubmitting}>
            <option value={1}>Central Library</option>
            <option value={2}>MBA Library / KBS</option>
          </select>
        </div>

        <div class="cyber-input-group">
          <label for="b-subject">Subject Category</label>
          <input id="b-subject" type="text" bind:value={subject} placeholder="e.g. COMPUTER SCIENCE" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-location">Shelf Location / Racks</label>
          <input id="b-location" type="text" bind:value={location} placeholder="e.g. B3-4 or 9.10.2" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-edition">Edition</label>
          <input id="b-edition" type="text" bind:value={edition} placeholder="e.g. 1st or 2nd Ed" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-year">Publishing Year</label>
          <input id="b-year" type="number" bind:value={pubYear} placeholder="e.g. 2024" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-price">Price (INR)</label>
          <input id="b-price" type="number" step="0.01" bind:value={price} placeholder="e.g. 450.00" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="b-isbn">ISBN / International Standard Code</label>
          <input id="b-isbn" type="text" bind:value={isbn} placeholder="e.g. 9780132350884" disabled={isSubmitting} />
        </div>
      </div>

      <div class="search-actions-row" style="margin-top: 2rem;">
        <button class="action-btn-secondary font-mono" on:click={() => { accNo = ''; title = ''; author = ''; price = ''; isbn = ''; subject = ''; location = ''; }} disabled={isSubmitting}>
          Clear Form
        </button>
        <button class="action-btn-primary" on:click={handleSubmit} disabled={isSubmitting}>
          {isSubmitting ? 'Adding Book...' : '📖 Insert Book'}
        </button>
      </div>
    </div>
  </div>
</div>

<style>
  .header-with-icon {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 0.2rem;
  }
  .header-with-icon h3 {
    margin: 0;
  }
  .alert-box {
    display: flex;
    align-items: center;
    gap: 0.8rem;
    padding: 1rem 1.4rem;
    border-radius: 10px;
    margin-bottom: 1.8rem;
    font-size: 0.88rem;
    font-family: 'DM Sans', sans-serif;
  }
  .alert-success {
    background: rgba(78, 173, 133, 0.08);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.2);
  }
  .alert-error {
    background: rgba(224, 108, 108, 0.08);
    color: var(--danger);
    border: 1px solid rgba(224, 108, 108, 0.2);
  }
  .alert-icon {
    font-size: 1.1rem;
    font-weight: bold;
  }
  .alert-text {
    line-height: 1.4;
  }
</style>
