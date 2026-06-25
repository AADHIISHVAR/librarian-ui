<script>
  import { addMember, fetchFilterOptions } from '../lib/api';
  import { onMount } from 'svelte';

  let idNo = '';
  let name = '';
  let className = 'STUDENT';
  let studyYear = new Date().getFullYear().toString();
  let deptNo = 8; // Default CSE
  let catNo = 2; // Default UG STUDENT
  let phone = '';
  let email = '';
  let regNo = '';
  let gender = 'M';

  let departments = [];
  let categories = [];
  let isLoadingOptions = false;

  let isSubmitting = false;
  let successMessage = '';
  let errorMessage = '';

  // Synchronize regNo with idNo when user types (common behavior)
  $: if (idNo) {
    regNo = idNo;
  }

  onMount(async () => {
    isLoadingOptions = true;
    try {
      const options = await fetchFilterOptions();
      if (options.departments_meta && options.departments_meta.length > 0) {
        departments = options.departments_meta;
      } else {
        fallbackDepts();
      }
      if (options.categories_meta && options.categories_meta.length > 0) {
        categories = options.categories_meta;
      } else {
        fallbackCats();
      }
    } catch (e) {
      console.error('Failed to load DB filter options:', e);
      fallbackDepts();
      fallbackCats();
    } finally {
      isLoadingOptions = false;
    }
  });

  function fallbackDepts() {
    departments = [
      { id: 1, name: 'CHEMISTRY' },
      { id: 2, name: 'PHYSICS' },
      { id: 3, name: 'MATHS' },
      { id: 4, name: 'MECH' },
      { id: 5, name: 'ENGLISH' },
      { id: 6, name: 'EEE' },
      { id: 7, name: 'ECE' },
      { id: 8, name: 'CSE' },
      { id: 9, name: 'LIBRARY' },
      { id: 26, name: 'B.TECH. IT' },
      { id: 27, name: 'B.TECH CS&BS' },
      { id: 28, name: 'MBA' },
      { id: 30, name: 'B.TECH. AI & DS' },
      { id: 31, name: 'TAMIL' },
      { id: 42, name: 'MCA' },
      { id: 45, name: 'SCIENCE & HUMANITIES' },
      { id: 47, name: 'CDT' }
    ];
  }

  function fallbackCats() {
    categories = [
      { id: 1, name: 'TEACHING STAFF' },
      { id: 2, name: 'UG STUDENT' },
      { id: 3, name: 'NONTEACHING STAFF' },
      { id: 4, name: 'MBA STUDENT' },
      { id: 5, name: 'PG STUDENT' }
    ];
  }

  async function handleSubmit() {
    if (!idNo.trim() || !name.trim()) {
      errorMessage = 'Student ID (Roll No) and Full Name are mandatory fields.';
      return;
    }

    isSubmitting = true;
    errorMessage = '';
    successMessage = '';

    try {
      const payload = {
        id_no: idNo.trim().toUpperCase(),
        name: name.trim().toUpperCase(),
        class: className.toUpperCase(),
        study_year: studyYear.trim(),
        dept_no: parseInt(deptNo),
        cat_no: parseInt(catNo),
        phone: phone.trim(),
        e_mail: email.trim(),
        reg_no: regNo.trim().toUpperCase(),
        gender
      };

      const result = await addMember(payload);
      if (result.status === 'success') {
        successMessage = `Successfully enrolled member: ${name.toUpperCase()} (${idNo.toUpperCase()})`;
        // Reset form
        idNo = '';
        name = '';
        phone = '';
        email = '';
        regNo = '';
      } else {
        errorMessage = result.message || 'Failed to add member.';
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
          <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
          <circle cx="8.5" cy="7" r="4" />
          <line x1="20" y1="8" x2="20" y2="14" />
          <line x1="23" y1="11" x2="17" y2="11" />
        </svg>
        <h3>Add New Member</h3>
      </div>
      <p class="panel-subtitle">Register a new student or staff borrower in the library transaction database.</p>
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
          <label for="m-id">Roll Number / ID *</label>
          <input id="m-id" type="text" bind:value={idNo} placeholder="e.g. 2K24AIDS121" required disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="m-name">Full Name *</label>
          <input id="m-name" type="text" bind:value={name} placeholder="e.g. BARATH S" required disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="m-reg">Register Number (Defaults to ID)</label>
          <input id="m-reg" type="text" bind:value={regNo} placeholder="e.g. 2K24AIDS121" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="m-class">Class / Designation</label>
          <select id="m-class" class="cyber-select" bind:value={className} disabled={isSubmitting}>
            <option value="STUDENT">STUDENT</option>
            <option value="ASSISTANT PROFESSOR">ASSISTANT PROFESSOR</option>
            <option value="ASSOCIATE PROFESSOR">ASSOCIATE PROFESSOR</option>
            <option value="PROFESSOR">PROFESSOR</option>
            <option value="NONTEACHING STAFF">NONTEACHING STAFF</option>
          </select>
        </div>

        <div class="cyber-input-group">
          <label for="m-dept">Department</label>
          <select id="m-dept" class="cyber-select" bind:value={deptNo} disabled={isSubmitting || isLoadingOptions}>
            {#each departments as dept}
              <option value={dept.id}>{dept.name}</option>
            {/each}
          </select>
        </div>

        <div class="cyber-input-group">
          <label for="m-cat">Borrower Category</label>
          <select id="m-cat" class="cyber-select" bind:value={catNo} disabled={isSubmitting || isLoadingOptions}>
            {#each categories as cat}
              <option value={cat.id}>{cat.name}</option>
            {/each}
          </select>
        </div>

        <div class="cyber-input-group">
          <label for="m-year">Academic Year / Year Joined</label>
          <input id="m-year" type="text" bind:value={studyYear} placeholder="e.g. 2025" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="m-gender">Gender</label>
          <select id="m-gender" class="cyber-select" bind:value={gender} disabled={isSubmitting}>
            <option value="M">Male</option>
            <option value="F">Female</option>
          </select>
        </div>

        <div class="cyber-input-group">
          <label for="m-phone">Mobile Contact (91xxxx)</label>
          <input id="m-phone" type="text" bind:value={phone} placeholder="e.g. 919876543210" disabled={isSubmitting} />
        </div>

        <div class="cyber-input-group">
          <label for="m-email">Email Address</label>
          <input id="m-email" type="email" bind:value={email} placeholder="e.g. name@kiot.ac.in" disabled={isSubmitting} />
        </div>
      </div>

      <div class="search-actions-row" style="margin-top: 2rem;">
        <button class="action-btn-secondary font-mono" on:click={() => { idNo = ''; name = ''; phone = ''; email = ''; regNo = ''; }} disabled={isSubmitting}>
          Clear Form
        </button>
        <button class="action-btn-primary" on:click={handleSubmit} disabled={isSubmitting}>
          {isSubmitting ? 'Registering Member...' : '👤 Enroll Member'}
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
