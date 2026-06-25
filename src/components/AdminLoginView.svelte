<script>
  import { onMount, onDestroy } from 'svelte';
  import { 
    sendWhatsAppMessage, 
    fetchInstances, 
    createInstance, 
    connectInstance, 
    logoutInstance,
    fetchOverdueBooks,
    getCachedQR,
    deleteInstance,
    requestPairingCode,
    fetchStudentsDueOverview,
    fetchFilterOptions,
    markBookReturned,
    searchMember,
    fetchDuelistReport,
    login,
    clearToken
  } from '../lib/api';
  import AddMemberView from './AddMemberView.svelte';
  import AddBookView from './AddBookView.svelte';


  let username = "";
  let password = "";
  let isLoggedIn = false;
  let error = "";
  let activeTab = "dashboard"; // dashboard | students-due | whatsapp | logs
  let devUsernames = ["AADHIISHVAR"];
  let newUsernameInput = "";
  let isSavingSettings = false;
  let settingsSaveStatus = null;

  function updateUrl(path) {
    if (window.location.pathname !== path) {
      window.history.pushState(null, '', path);
    }
  }

  function syncTabFromUrl() {
    const path = window.location.pathname;
    if (path.includes('/master_user_search')) {
      activeTab = 'master-search';
    } else if (path.includes('/students_due')) {
      activeTab = 'students-due';
    } else if (path.includes('/whatsapp')) {
      activeTab = 'whatsapp';
    } else if (path.includes('/logs')) {
      activeTab = 'logs';
    } else if (path.includes('/reports')) {
      activeTab = 'reports';
    } else if (path.includes('/add_member')) {
      activeTab = 'add-member';
    } else if (path.includes('/add_book')) {
      activeTab = 'add-book';
    } else if (path.includes('/settings')) {
      activeTab = 'settings';
    } else if (path.startsWith('/admin_dashboard')) {
      activeTab = 'dashboard';
    }
  }

  onMount(() => {
    syncTabFromUrl();
    window.addEventListener('popstate', syncTabFromUrl);
    return () => window.removeEventListener('popstate', syncTabFromUrl);
  });

  // Reactive URL synchronization
  $: {
    if (isLoggedIn) {
      if (activeTab === 'dashboard') updateUrl('/admin_dashboard');
      else if (activeTab === 'master-search') updateUrl('/admin_dashboard/master_user_search');
      else if (activeTab === 'students-due') updateUrl('/admin_dashboard/students_due');
      else if (activeTab === 'whatsapp') updateUrl('/admin_dashboard/whatsapp');
      else if (activeTab === 'logs') updateUrl('/admin_dashboard/logs');
      else if (activeTab === 'reports') updateUrl('/admin_dashboard/reports');
      else if (activeTab === 'add-member') updateUrl('/admin_dashboard/add_member');
      else if (activeTab === 'add-book') updateUrl('/admin_dashboard/add_book');
      else if (activeTab === 'settings') updateUrl('/admin_dashboard/settings');
    }
  }

  // WhatsApp Connection State
  let connStatus = "checking"; // checking | login | dashboard
  let qrCode = null;
  let pairingCode = null;
  let phoneNumber = "";
  let isPairingLoading = false;
  let instances = [];
  let selectedInstance = "";
  let newInstanceName = "";
  let isCreatingInstance = false;

  // Messaging state
  let recipient = "91";
  let dueDate = "";
  let daysLimit = "7";
  let message = "";
  let infoMsg = "";
  let isSending = false;

  let overdueBooks = [];
  let isLoadingOverdue = false;

  // Students Due Overview State
  let studentsDue = [];
  let isLoadingStudentsDue = false;
  let studentsDueTotal = 0;
  let studentsDueLimit = 50;
  let studentsDueOffset = 0;
  let filterDepartment = "";
  let filterCategory = "";
  let filterOverdueOnly = false;
  let filterClasses = [];
  let filterSearchQuery = "";
  let filterStudyYear = "";
  let filterGender = "All";
  let filterDepartments = [];
  let filterCategories = [];
  let studentsDueSortKey = "due_date";
  let studentsDueSortAsc = true;

  let pollInterval;
  let isPolling = false;

  // System activity logs console
  let systemLogs = [];
  function logEvent(msg, type = "info") {
    const time = new Date().toLocaleTimeString();
    systemLogs = [{ time, msg, type }, ...systemLogs].slice(0, 100);
  }

  // Preset Message Templates
  const templates = [
    {
      label: "⚠️ Standard Overdue Alert",
      text: "Reminder: The book '{title}' (Acc No: {acc}) was due on {due}. Please return it to the library at the earliest to avoid further fines."
    },
    {
      label: "🚨 Urgent Return Notice",
      text: "URGENT NOTICE: Book '{title}' (Acc No: {acc}) is severely overdue. Return it within 24 hours or your library borrowing privileges will be suspended."
    },
    {
      label: "📢 General Library Update",
      text: "Hello! This is a notice from the College Library regarding your active borrow status. Please verify your currently issued items."
    }
  ];

  function applyTemplate(templateText, student = null) {
    if (student) {
      message = templateText
        .replace("{title}", student.title)
        .replace("{acc}", student.acc_no)
        .replace("{due}", student.due_date);
      recipient = student.phone.startsWith('91') ? student.phone : `91${student.phone}`;
      dueDate = student.due_date;
      logEvent(`Applied message template for student ${student.student_name}`, "info");
    } else {
      message = templateText
        .replace("{title}", "Library Book")
        .replace("{acc}", "XXXX")
        .replace("{due}", new Date().toLocaleDateString());
      logEvent(`Applied message template (generic)`, "info");
    }
  }

  // Master Search state
  let masterSearchRoll = "";
  let masterSearchReg = "";
  let masterSearchDept = "";
  let masterSearchBatch = "";
  let masterSearchPhone = "";
  let masterSearchName = "";
  let masterSearchResults = [];
  let isMasterSearching = false;
  let selectedMemberDetail = null;

  function resetMasterSearch() {
    masterSearchRoll = "";
    masterSearchReg = "";
    masterSearchDept = "";
    masterSearchBatch = "";
    masterSearchPhone = "";
    masterSearchName = "";
    masterSearchResults = [];
    selectedMemberDetail = null;
    logEvent("Reset Master Search fields", "info");
  }

  async function handleMasterSearch() {
    isMasterSearching = true;
    selectedMemberDetail = null;
    logEvent("Initiated Master User Search", "info");
    try {
      masterSearchResults = await searchMember({
        roll_no: masterSearchRoll,
        reg_no: masterSearchReg,
        dept: masterSearchDept,
        batch: masterSearchBatch,
        phone: masterSearchPhone,
        name: masterSearchName,
      });
      logEvent(`Master Search finished: ${masterSearchResults.length} matches found`, "success");
    } catch (e) {
      infoMsg = "❌ Search failed: " + e.message;
      logEvent(`Master Search failed: ${e.message}`, "error");
    } finally {
      isMasterSearching = false;
    }
  }

  function selectMember(member) {
    selectedMemberDetail = member;
    logEvent(`Selected member detail view: ${member.name} (${member.id_no})`, "info");
  }

  // Reports State
  let reportDept = "All Departments";
  let reportCategory = "All Categories";
  const availableClasses = ["STUDENT", "ASSISTANT PROFESSOR", "ASSOCIATE PROFESSOR", "PROFESSOR", "NONTEACHING STAFF"];
  let selectedClasses = [];
  let reportStudyYear = "";
  let reportGender = "All";
  let reportIdPattern = "";
  let reportMatchType = "left"; // "exact" | "like" | "left" | "right"
  let reportActiveStatus = "active"; // "active" | "old" | "both"
  let reportFineRate = 0.50;
  let reportPrintOption = "window"; // "window" | "pdf"
  let reportResults = null;
  let isGeneratingReport = false;

  function toggleClass(className) {
    if (selectedClasses.includes(className)) {
      selectedClasses = selectedClasses.filter(c => c !== className);
    } else {
      selectedClasses = [...selectedClasses, className];
    }
  }

  function toggleFilterClass(className) {
    if (filterClasses.includes(className)) {
      filterClasses = filterClasses.filter(c => c !== className);
    } else {
      filterClasses = [...filterClasses, className];
    }
    fetchStudentsDue(true);
  }

  function resetReports() {
    reportDept = "All Departments";
    reportCategory = "All Categories";
    selectedClasses = [];
    reportStudyYear = "";
    reportGender = "All";
    reportIdPattern = "";
    reportMatchType = "left";
    reportActiveStatus = "active";
    reportFineRate = 0.50;
    reportPrintOption = "window";
    reportResults = null;
    logEvent("Reset Reports fields", "info");
  }

  async function handleGenerateReport() {
    isGeneratingReport = true;
    reportResults = null;
    logEvent("Generating Member Due List Report...", "info");
    try {
      const res = await fetchDuelistReport({
        department: reportDept === "All Departments" ? null : reportDept,
        category: reportCategory === "All Categories" ? null : reportCategory,
        class_name: selectedClasses.length === 0 ? null : selectedClasses.join(','),
        study_year: reportStudyYear || null,
        gender: reportGender === "All" ? null : reportGender,
        id_pattern: reportIdPattern || null,
        match_type: reportMatchType,
        active_status: reportActiveStatus,
        fine_rate: reportFineRate
      });
      reportResults = res;
      logEvent(`Report generated successfully: ${reportResults.members.length} members found.`, "success");
      
      if (reportPrintOption === "pdf") {
        setTimeout(() => {
          window.print();
        }, 500);
      }
    } catch (e) {
      infoMsg = "❌ Report failed: " + e.message;
      logEvent(`Report generation failed: ${e.message}`, "error");
    } finally {
      isGeneratingReport = false;
    }
  }

  // Reactive Stats computations
  $: overdueRate = studentsDueTotal > 0 ? Math.round((overdueBooks.length / studentsDueTotal) * 100) : 0;

  $: deptStats = (() => {
    let counts = {};
    // Calculate stats from studentsDue if available
    studentsDue.forEach(s => {
      let d = s.department || "General";
      counts[d] = (counts[d] || 0) + (s.days_overdue > 0 ? 1 : 0);
    });
    // Add default counts if empty for beautiful visual presentation
    if (Object.keys(counts).length === 0) {
      return [
        { name: "Central Library", count: overdueBooks.length },
        { name: "MBA / KBS", count: 0 },
        { name: "Competitive Section", count: 0 }
      ];
    }
    return Object.entries(counts)
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);
  })();

  $: maxDeptCount = Math.max(...deptStats.map(d => d.count), 1);

  async function checkSetup() {
    try {
      const raw = await fetchInstances();
      instances = Array.isArray(raw) ? raw : raw?.instances ?? [];
      
      if (!selectedInstance) {
        if (instances.length > 0) {
          // Auto select first instance if available
          selectedInstance = instances[0].name;
          logEvent(`Auto-selected first available instance: ${selectedInstance}`, "info");
        } else {
          console.log("[admin] No instance selected, prompting for creation");
          connStatus = "login";
          return;
        }
      }

      const inst = instances.find((i) => i.name === selectedInstance);
      if (inst) {
        if (inst.connectionStatus === "open") {
          if (connStatus !== "dashboard") {
            connStatus = "dashboard";
            logEvent(`WhatsApp Gateway connected on instance [${selectedInstance}]`, "success");
          }
        } else {
          connStatus = "login";
          if (connStatus !== "login") {
            logEvent(`Instance [${selectedInstance}] disconnected. Waiting for authentication.`, "warning");
          }
        }
      } else {
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
      logEvent(`Requesting Pairing Code for ${num} on session ${selectedInstance}...`, "info");
      try { await logoutInstance(selectedInstance); } catch(e) {}
      await new Promise(r => setTimeout(r, 1000));
      
      try {
        const res = await requestPairingCode(selectedInstance, num);
        pairingCode = res?.pairingCode ?? res?.data?.pairingCode ?? null;
        if (pairingCode) {
          logEvent(`Pairing Code successfully generated: ${pairingCode}`, "success");
        }
      } catch (e) {
        console.error("[admin] pairing code error:", e);
        error = "Pairing code request failed: " + e.message;
        logEvent(`Failed generating pairing code: ${e.message}`, "error");
      }
      isPairingLoading = false;
      return;
    }

    try {
      console.log(`[admin] Fetching connection data for ${selectedInstance} (QR/Pairing)...`);
      if (!num) {
        const cached = await getCachedQR(selectedInstance);
        if (cached && (cached.code || cached.base64)) {
          console.log(`[admin] Using cached QR for ${selectedInstance}`);
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
          if (qrCode) {
            logEvent("Using cached QR code", "info");
            return;
          }
        }
      }

      const res = await connectInstance(selectedInstance, num);
      if (res?.error) {
        console.error("[admin] connect API error:", res.message);
        return;
      }
      
      pairingCode = res?.pairingCode ?? res?.data?.pairingCode ?? null;
      const qrData = res?.qrcode ?? res?.data?.qrcode ?? res;
      let imgSrc = null;
      if (qrData?.base64) {
        imgSrc = qrData.base64.startsWith("data:") ? qrData.base64 : `data:image/png;base64,${qrData.base64}`;
      } else if (qrData?.code && typeof qrData.code === "string") {
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
        logEvent("New QR Code generated from Evolution API server", "info");
      }
      if (qrData?.pairingCode) {
        pairingCode = qrData.pairingCode;
        logEvent(`Pairing Code received: ${pairingCode}`, "success");
      }
    } catch (e) {
      console.error("[admin] fetchConnData error:", e);
    }
    isPairingLoading = false;
  }

  async function handleCreateInstance() {
    if (!newInstanceName) return;
    isCreatingInstance = true;
    logEvent(`Creating instance: ${newInstanceName}...`, "info");
    try {
      const res = await createInstance(newInstanceName);
      selectedInstance = newInstanceName;
      newInstanceName = "";
      await new Promise(r => setTimeout(r, 2000));
      await checkSetup();
      await fetchConnData();
      logEvent(`Successfully created and loaded instance: ${selectedInstance}`, "success");
      infoMsg = `Instance ${selectedInstance} created successfully!`;
    } catch (e) {
      console.error("[admin] Create instance failed:", e);
      error = "Failed to create instance: " + e.message;
      logEvent(`Create instance failed: ${e.message}`, "error");
    } finally {
      isCreatingInstance = false;
    }
  }

  async function handleDeleteInstance() {
    if (!selectedInstance) return;
    if (!confirm(`Are you sure you want to delete instance ${selectedInstance}? This cannot be undone.`)) return;
    
    logEvent(`Deleting instance ${selectedInstance}...`, "warning");
    try {
      await deleteInstance(selectedInstance);
      logEvent(`Deleted instance ${selectedInstance}`, "success");
      selectedInstance = "";
      await checkSetup();
      infoMsg = `Instance deleted successfully.`;
    } catch (e) {
      error = "Failed to delete instance: " + e.message;
      logEvent(`Delete instance failed: ${e.message}`, "error");
    }
  }

  function addUsername() {
    const trimmed = newUsernameInput.trim();
    if (trimmed && !devUsernames.includes(trimmed)) {
      devUsernames = [...devUsernames, trimmed];
    }
    newUsernameInput = "";
  }

  function removeUsername(index) {
    devUsernames = devUsernames.filter((_, i) => i !== index);
  }

  async function fetchSettings() {
    try {
      const res = await fetch("/api/settings/developer_username");
      if (res.ok) {
        const data = await res.json();
        if (data && data.value) {
          devUsernames = data.value.split(",").map(u => u.trim()).filter(Boolean);
        }
      }
    } catch (e) {
      console.warn("Failed to fetch settings:", e);
    }
  }

  async function saveSettings() {
    isSavingSettings = true;
    settingsSaveStatus = null;
    try {
      const res = await fetch("/api/settings", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer hellowork.1234",
          "x-librarian-key": "hellowork.1234"
        },
        body: JSON.stringify({
          key: "developer_username",
          value: devUsernames.join(",")
        })
      });
      if (res.ok) {
        settingsSaveStatus = { success: true, msg: "Settings saved successfully!" };
        logEvent("System settings updated: developer_username", "success");
      } else {
        throw new Error(`Failed with status ${res.status}`);
      }
    } catch (e) {
      settingsSaveStatus = { success: false, msg: `Error saving settings: ${e.message}` };
      logEvent(`Failed to update system settings: ${e.message}`, "error");
    } finally {
      isSavingSettings = false;
    }
  }

  let isLoginLoading = false;

  async function handleLogin() {
    if (!username || !password) {
      error = "Username and password are required";
      return;
    }
    isLoginLoading = true;
    error = "";
    try {
      const data = await login(username, password);
      if (data && data.token) {
        isLoggedIn = true;
        logEvent("Administrator authenticated successfully via token verification", "success");
        startPolling();
        fetchOverdue();
        fetchStudentsDue(true);
        fetchSettings();
      } else {
        throw new Error("No token returned from server");
      }
    } catch (e) {
      error = e.message || "Invalid username or password";
      logEvent(`Authentication failed: ${error}`, "error");
    } finally {
      isLoginLoading = false;
    }
  }

  async function handleInstanceChange() {
    logEvent(`Switched active session to: ${selectedInstance}`, "info");
    await checkSetup();
    await fetchConnData();
  }

  async function runPoll() {
    if (isPolling) return;
    isPolling = true;
    try {
      await checkSetup();
      if (selectedInstance && connStatus === "login" && !isPairingLoading) {
        await fetchConnData();
      }
    } finally {
      isPolling = false;
    }
  }

  async function forceReset() {
    if (!confirm(`This will disconnect ${selectedInstance} and clear the session. Continue?`)) return;
    logEvent(`Resetting session ${selectedInstance}...`, "warning");
    try {
        connStatus = "checking";
        await logoutInstance(selectedInstance);
        qrCode = null;
        pairingCode = null;
        logEvent(`Session ${selectedInstance} reset. Requesting new QR...`, "info");
        infoMsg = `Instance ${selectedInstance} reset successfully. Generating new QR...`;
        setTimeout(runPoll, 2000);
    } catch (e) {
        error = "Reset failed: " + e.message;
        logEvent(`Reset session failed: ${e.message}`, "error");
        connStatus = "login";
    }
  }

  function startPolling() {
    void runPoll();
    pollInterval = setInterval(runPoll, 4000);
  }

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
  });

  function handleLogout() {
    isLoggedIn = false;
    username = "";
    password = "";
    clearToken();
    logEvent("Administrator logged out", "warning");
    if (pollInterval) clearInterval(pollInterval);
  }

  async function sendMessage() {
    if (recipient.length < 10 || !message) {
      infoMsg = "⚠️ Please enter a valid number and message.";
      return;
    }

    isSending = true;
    infoMsg = "🤫 Sending secure message (anti-ban active)...";
    logEvent(`Dispatching WhatsApp message to ${recipient} (anti-ban delays active)`, "info");
    
    let fullMessage = message;
    if (dueDate) {
      fullMessage += `\n\n📅 Due Date: ${dueDate}\n⏳ Days Limit: ${daysLimit}`;
    }

    try {
      const res = await sendWhatsAppMessage(selectedInstance, recipient, fullMessage);
      if (res.status === "success") {
        infoMsg = "✅ " + res.message;
        logEvent(`Message successfully delivered to ${recipient}`, "success");
        message = "";
      } else {
        infoMsg = "❌ " + res.message;
        logEvent(`Delivery failed for ${recipient}: ${res.message}`, "error");
      }
    } catch (e) {
      infoMsg = "❌ Error: " + e.message;
      logEvent(`Delivery error: ${e.message}`, "error");
    } finally {
      isSending = false;
    }
  }

  async function fetchOverdue() {
    isLoadingOverdue = true;
    try {
      overdueBooks = await fetchOverdueBooks();
      logEvent(`Loaded ${overdueBooks.length} overdue entries`, "info");
    } catch (e) {
      infoMsg = "❌ Error fetching overdue: " + e.message;
      logEvent(`Overdue fetch failed: ${e.message}`, "error");
    } finally {
      isLoadingOverdue = false;
    }
  }

  async function fetchFilterOptionsData() {
    try {
      const data = await fetchFilterOptions();
      filterDepartments = data.departments || [];
      filterCategories = data.categories || [];
      logEvent(`Fetched ${filterDepartments.length} departments & ${filterCategories.length} categories`, "info");
    } catch (e) {
      console.error("[admin] fetchFilterOptionsData error:", e);
    }
  }

  async function fetchStudentsDue(resetOffset = false) {
    if (resetOffset) {
      studentsDueOffset = 0;
    }
    isLoadingStudentsDue = true;
    try {
      const data = await fetchStudentsDueOverview({
        department: filterDepartment || undefined,
        category: filterCategory || undefined,
        overdue_only: filterOverdueOnly,
        limit: studentsDueLimit,
        offset: studentsDueOffset,
        class_name: filterClasses.length === 0 ? undefined : filterClasses.join(','),
        search_query: filterSearchQuery || undefined,
        study_year: filterStudyYear || undefined,
        gender: filterGender === "All" ? undefined : filterGender,
      });
      studentsDue = data.students || [];
      studentsDueTotal = data.total || 0;
      logEvent(`Loaded borrowers directory: page ${Math.floor(studentsDueOffset / studentsDueLimit) + 1}`, "info");
    } catch (e) {
      infoMsg = "❌ Error fetching students due: " + e.message;
      logEvent(`Borrowers fetch failed: ${e.message}`, "error");
    } finally {
      isLoadingStudentsDue = false;
    }
  }

  function handleSort(key) {
    if (studentsDueSortKey === key) {
      studentsDueSortAsc = !studentsDueSortAsc;
    } else {
      studentsDueSortKey = key;
      studentsDueSortAsc = true;
    }
    studentsDue = [...studentsDue].sort((a, b) => {
      let aVal = a[key];
      let bVal = b[key];
      if (typeof aVal === 'string') {
        aVal = aVal.toLowerCase();
        bVal = bVal.toLowerCase();
      }
      if (aVal < bVal) return studentsDueSortAsc ? -1 : 1;
      if (aVal > bVal) return studentsDueSortAsc ? 1 : -1;
      return 0;
    });
    logEvent(`Sorted table by: ${key} (${studentsDueSortAsc ? 'Ascending' : 'Descending'})`, "info");
  }

  function notifyStudent(student) {
    if (!student.phone) {
      infoMsg = "❌ No phone number available for this student";
      logEvent(`Failed notifying ${student.student_name}: Missing phone number`, "warning");
      return;
    }
    recipient = student.phone.startsWith('91') ? student.phone : `91${student.phone}`;
    message = `Reminder: You have overdue book '${student.title}' (Acc: ${student.acc_no}) due on ${student.due_date}. Please return it to the library.`;
    dueDate = student.due_date;
    activeTab = 'dashboard';
    infoMsg = `📱 Ready to notify ${student.student_name} (${student.id_no}) for "${student.title}"`;
    logEvent(`Pre-populated notification form for student ${student.id_no}`, "info");
  }

  async function markAsReturned(student) {
    if (!confirm(`Mark "${student.title}" (Acc: ${student.acc_no}) as returned for ${student.student_name} (${student.id_no})?`)) {
      return;
    }
    try {
      const res = await markBookReturned(student.id_no, student.acc_no);
      if (res.success) {
        infoMsg = `✅ ${res.message}`;
        logEvent(`Returned book [${student.acc_no}] for student ${student.id_no}`, "success");
        fetchStudentsDue();
        fetchOverdue();
      } else {
        infoMsg = `❌ ${res.message}`;
        logEvent(`Return operation failed: ${res.message}`, "error");
      }
    } catch (e) {
      infoMsg = `❌ Error: ${e.message}`;
      logEvent(`Return error: ${e.message}`, "error");
    }
  }

  async function initAdmin() {
    await fetchFilterOptionsData();
  }

  onMount(initAdmin);
</script>

<div class="admin-container">
  {#if !isLoggedIn}
    <!-- GORGEOUS SECURITY PORTAL LOGIN -->
    <div class="login-wrapper">
      <div class="login-backdrop-glow"></div>
      <div class="login-box">
        <div class="login-header-glow"></div>
        <div class="cyber-badge font-mono">
          <span class="pulse-dot pulse-gold"></span>
          SECURE ADMINISTRATIVE GATE
        </div>
        <h2>Librarian Console</h2>
        <p class="login-desc">Enter authorization credentials to unlock system analytics, WhatsApp gateways, and borrow auditing tools.</p>
        
        <div class="cyber-input-group">
          <label for="username">Administrator ID</label>
          <div class="cyber-input-wrap">
            <span class="cyber-input-icon">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
            </span>
            <input id="username" type="text" bind:value={username} placeholder="Administrator username" />
          </div>
        </div>

        <div class="cyber-input-group">
          <label for="password">System Access Key</label>
          <div class="cyber-input-wrap">
            <span class="cyber-input-icon">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </span>
            <input id="password" type="password" bind:value={password} placeholder="••••••••" on:keydown={(e) => e.key === 'Enter' && handleLogin()}/>
          </div>
        </div>

        {#if error}
          <div class="cyber-error-box">
            <svg class="error-svg-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <span>{error}</span>
          </div>
        {/if}

        <button class="cyber-login-btn" on:click={handleLogin}>
          <span>Unlock Panel</span>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M5 12h14M12 5l7 7-7 7" />
          </svg>
        </button>
      </div>
    </div>
  {:else}
    <!-- GORGEOUS FULL DASHBOARD SYSTEM -->
    <div class="dashboard-container">
      
      <!-- SIDEBAR -->
      <aside class="dashboard-sidebar">
        <div class="sidebar-brand">
          <div class="brand-logo">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" stroke-width="2">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
            <span>Librarian Admin</span>
          </div>
          <div class="system-status-indicator {connStatus === 'dashboard' ? 'status-online' : 'status-offline'}">
            <span class="status-pulse-dot"></span>
            <span class="font-mono">{connStatus === 'dashboard' ? 'EVOLUTION: LIVE' : 'EVOLUTION: STANDBY'}</span>
          </div>
        </div>

        <nav class="sidebar-nav">
          <button class="nav-item" class:active={activeTab === 'dashboard'} on:click={() => activeTab = 'dashboard'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="7" height="9" />
              <rect x="14" y="3" width="7" height="5" />
              <rect x="14" y="12" width="7" height="9" />
              <rect x="3" y="16" width="7" height="5" />
            </svg>
            <span>Overview & Dispatch</span>
          </button>
          
          <button class="nav-item" class:active={activeTab === 'students-due'} on:click={() => { activeTab = 'students-due'; fetchStudentsDue(true); }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
              <circle cx="9" cy="7" r="4" />
              <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
              <path d="M16 3.13a4 4 0 0 1 0 7.75" />
            </svg>
            <span>Borrowers Registry</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'master-search'} on:click={() => { activeTab = 'master-search'; resetMasterSearch(); }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="11" cy="11" r="8" />
              <line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
            <span>Master User Search</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'reports'} on:click={() => { activeTab = 'reports'; resetReports(); }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <line x1="16" y1="13" x2="8" y2="13" />
              <line x1="16" y1="17" x2="8" y2="17" />
              <circle cx="9" cy="9" r="1" />
            </svg>
            <span>Due List Reports</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'add-member'} on:click={() => activeTab = 'add-member'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
              <circle cx="8.5" cy="7" r="4" />
              <line x1="20" y1="8" x2="20" y2="14" />
              <line x1="23" y1="11" x2="17" y2="11" />
            </svg>
            <span>Add Member</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'add-book'} on:click={() => activeTab = 'add-book'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
              <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
              <line x1="12" y1="6" x2="12" y2="18" />
              <line x1="9" y1="12" x2="15" y2="12" />
            </svg>
            <span>Add Book</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'whatsapp'} on:click={() => activeTab = 'whatsapp'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
            </svg>
            <span>Gateway Settings</span>
          </button>

          <button class="nav-item" class:active={activeTab === 'logs'} on:click={() => activeTab = 'logs'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="4 17 10 11 15 16 20 9" />
              <polyline points="13 9 20 9 20 16" />
            </svg>
            <span>Activity Logs</span>
            {#if systemLogs.length > 0}
              <span class="badge-count">{systemLogs.length}</span>
            {/if}
          </button>

          <button class="nav-item" class:active={activeTab === 'settings'} on:click={() => activeTab = 'settings'}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
            <span>System Settings</span>
          </button>
        </nav>

        <div class="sidebar-footer">
          <div class="admin-profile">
            <div class="admin-avatar">AD</div>
            <div class="admin-info">
              <div class="admin-name">Administrator</div>
              <div class="admin-role">System Root</div>
            </div>
          </div>
          <button class="logout-btn" on:click={handleLogout}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
            </svg>
            <span>Sign Out</span>
          </button>
        </div>
      </aside>

      <!-- MAIN AREA -->
      <main class="dashboard-workspace">
        <!-- TOP STATUS HEADER -->
        <header class="workspace-header">
          <div class="breadcrumb font-mono">
            <span class="bc-parent">CONSOLE</span>
            <span class="bc-sep">/</span>
            <span class="bc-active">
              {activeTab === 'dashboard' ? 'OVERVIEW' : 
               activeTab === 'students-due' ? 'BORROWERS' : 
               activeTab === 'master-search' ? 'SEARCH' : 
               activeTab === 'reports' ? 'REPORTS' : 
               activeTab === 'add-member' ? 'ADD MEMBER' : 
               activeTab === 'add-book' ? 'ADD BOOK' : 
               activeTab === 'whatsapp' ? 'GATEWAY' : 
               activeTab === 'settings' ? 'SYSTEM SETTINGS' : 'SYSTEM LOGS'}
            </span>
          </div>

          <div class="header-actions">
            {#if connStatus === 'dashboard'}
              <div class="wa-status-badge badge-success font-mono">
                <span class="pulse-dot pulse-green"></span>
                <span>NODE: {selectedInstance}</span>
              </div>
            {:else}
              <div class="wa-status-badge badge-danger font-mono">
                <span class="pulse-dot pulse-red"></span>
                <span>NO SESSION LINKED</span>
              </div>
            {/if}
            <button class="header-refresh-btn" on:click={() => {
              logEvent("Manual dashboard reload triggered", "info");
              fetchOverdue();
              if (activeTab === 'students-due') fetchStudentsDue();
              checkSetup();
            }} title="Reload Data">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67" />
              </svg>
            </button>
          </div>
        </header>

        <!-- ALERTS BANNER -->
        {#if infoMsg}
          <div class="alert-banner animate-fade">
            <div class="alert-content">
              <span class="alert-icon">✦</span>
              <p>{infoMsg}</p>
            </div>
            <button class="alert-close-btn" on:click={() => infoMsg = ""}>×</button>
          </div>
        {/if}

        <!-- DASHBOARD TAB -->
        {#if activeTab === 'dashboard'}
          <!-- KPI ROW -->
          <div class="kpi-grid">
            <!-- WhatsApp Connection Card -->
            <div class="kpi-card {connStatus === 'dashboard' ? 'kpi-success' : 'kpi-warning'}">
              <div class="kpi-card-header">
                <span class="kpi-card-title">WhatsApp Gateway</span>
                <span class="kpi-card-icon">💬</span>
              </div>
              <div class="kpi-card-body">
                <div class="kpi-card-value">
                  {connStatus === 'dashboard' ? 'CONNECTED' : connStatus === 'checking' ? 'SYNCING' : 'OFFLINE'}
                </div>
                <div class="kpi-card-meta">
                  Session: <strong>{selectedInstance || 'None'}</strong>
                </div>
              </div>
              <!-- Mini visualizer (Signal wave) -->
              <div class="kpi-card-visual">
                <svg width="120" height="40" viewBox="0 0 120 40">
                  <path d="M 0 35 L 10 35 L 15 20 L 20 38 L 25 35 L 35 35 L 40 10 L 45 38 L 50 35 L 60 35 L 65 5 L 70 38 L 75 35 L 120 35" 
                        fill="none" 
                        stroke="var(--accent)" 
                        stroke-width="1.5" 
                        stroke-linecap="round" />
                </svg>
              </div>
            </div>

            <!-- Overdue Rate Card -->
            <div class="kpi-card kpi-purple">
              <div class="kpi-card-header">
                <span class="kpi-card-title">Overdue Alerts</span>
                <span class="kpi-card-icon">📚</span>
              </div>
              <div class="kpi-card-body">
                <div class="kpi-card-value">{overdueBooks.length}</div>
                <div class="kpi-card-meta">
                  Overdue Ratio: <strong>{overdueRate}%</strong>
                </div>
              </div>
              <!-- Radial progress ring -->
              <div class="kpi-card-radial">
                <svg width="36" height="36" viewBox="0 0 36 36" class="circular-chart">
                  <path class="circle-bg"
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  />
                  <path class="circle"
                    stroke-dasharray="{overdueRate}, 100"
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  />
                </svg>
              </div>
            </div>

            <!-- Active Sessions Card -->
            <div class="kpi-card">
              <div class="kpi-card-header">
                <span class="kpi-card-title">Active Sessions</span>
                <span class="kpi-card-icon">🔌</span>
              </div>
              <div class="kpi-card-body">
                <div class="kpi-card-value">{instances.length}</div>
                <div class="kpi-card-meta">
                  Active Instances Available
                </div>
              </div>
              <!-- Visual matrix grid -->
              <div class="kpi-card-visual opacity-50">
                <svg width="100" height="30" viewBox="0 0 100 30">
                  <circle cx="10" cy="15" r="3" fill="var(--border)" />
                  <circle cx="30" cy="15" r="3" fill="var(--border)" />
                  <circle cx="50" cy="15" r="3" fill="var(--border)" />
                  <circle cx="70" cy="15" r="3" fill="var(--border)" />
                  <circle cx="90" cy="15" r="3" fill="var(--accent)" />
                </svg>
              </div>
            </div>

            <!-- Total tracked borrowers -->
            <div class="kpi-card kpi-purple">
              <div class="kpi-card-header">
                <span class="kpi-card-title">Tracked Borrowers</span>
                <span class="kpi-card-icon">👥</span>
              </div>
              <div class="kpi-card-body">
                <div class="kpi-card-value">{studentsDueTotal}</div>
                <div class="kpi-card-meta">
                  Monitored active loans
                </div>
              </div>
              <!-- Area sparkline -->
              <div class="kpi-card-visual">
                <svg width="120" height="30" viewBox="0 0 120 30">
                  <path d="M 0 25 Q 15 15, 30 22 T 60 10 T 90 20 T 120 8 L 120 30 L 0 30 Z" 
                        fill="rgba(124, 111, 205, 0.15)" 
                        stroke="var(--accent2)" 
                        stroke-width="1.5" />
                </svg>
              </div>
            </div>
          </div>

          <!-- OVERVIEW SPLIT LAYOUT -->
          <div class="dashboard-grid animate-fade">
            <!-- Manual Alert Form -->
            <div class="dashboard-col">
              <div class="glass-card panel-card">
                <div class="panel-header">
                  <h3>Manual Alert Dispatcher</h3>
                  <p class="panel-subtitle">Draft and execute secure WhatsApp warnings directly to borrower devices.</p>
                </div>
                
                <div class="panel-body">
                  <div class="cyber-input-group">
                    <label for="recipient">Recipient Number</label>
                    <div class="cyber-input-wrap">
                      <span class="cyber-input-icon">📱</span>
                      <input id="recipient" type="text" bind:value={recipient} placeholder="91XXXXXXXXXX" disabled={isSending} />
                    </div>
                  </div>

                  <!-- Quick Templates -->
                  <div class="templates-section">
                    <span class="templates-label font-mono">CHOOSE TEMPLATE:</span>
                    <div class="templates-list">
                      {#each templates as t}
                        <button class="template-chip" on:click={() => applyTemplate(t.text)} title={t.text}>
                          {t.label}
                        </button>
                      {/each}
                    </div>
                  </div>

                  <div class="grid-form-fields">
                    <div class="cyber-input-group">
                      <label for="dueDate">Due Date (Optional)</label>
                      <input id="dueDate" type="date" bind:value={dueDate} disabled={isSending} style="color-scheme: dark;" />
                    </div>
                    <div class="cyber-input-group">
                      <label for="daysLimit">Grace Limit (Days)</label>
                      <input id="daysLimit" type="number" bind:value={daysLimit} placeholder="7" disabled={isSending} />
                    </div>
                  </div>

                  <div class="cyber-input-group">
                    <label for="message">Message Body</label>
                    <textarea id="message" bind:value={message} placeholder="Compose custom library notification content here..." disabled={isSending}></textarea>
                  </div>

                  <button class="action-btn-primary dispatch-btn" on:click={sendMessage} disabled={isSending}>
                    <span>{isSending ? 'Sending securely (Anti-Ban)...' : '⚡ Dispatch Alert'}</span>
                  </button>
                </div>
              </div>
            </div>

            <!-- Overdue Registry Preview & Chart Column -->
            <div class="dashboard-col col-right">
              <!-- Department stats bar chart -->
              <div class="glass-card panel-card chart-panel">
                <div class="panel-header">
                  <h3>Overdue distribution by Library</h3>
                  <p class="panel-subtitle">Distribution of overdue books by department/library segment.</p>
                </div>
                <div class="panel-body">
                  <div class="bar-chart-container">
                    {#each deptStats as dept}
                      <div class="bar-chart-row animate-fade">
                        <div class="bar-chart-label">
                          <span class="dept-name font-semibold">{dept.name}</span>
                          <span class="dept-count font-mono">{dept.count} books</span>
                        </div>
                        <div class="bar-chart-track">
                          <div class="bar-chart-fill" style="width: {(dept.count / maxDeptCount) * 100}%"></div>
                        </div>
                      </div>
                    {/each}
                  </div>
                </div>
              </div>

              <!-- Critical List Mini -->
              <div class="glass-card panel-card mini-registry-panel">
                <div class="panel-header-row">
                  <div>
                    <h3>Critical Overdue Registry</h3>
                    <p class="panel-subtitle">Active transactions that exceeded grace periods.</p>
                  </div>
                  <button class="table-refresh-link font-mono" on:click={fetchOverdue} disabled={isLoadingOverdue}>
                    {isLoadingOverdue ? 'SYNCING...' : '[RELOAD]'}
                  </button>
                </div>

                <div class="panel-body table-compact-container">
                  {#if isLoadingOverdue && overdueBooks.length === 0}
                    <div class="table-state-placeholder">
                      <div class="spinner-small"></div>
                      <p>Querying SQL database...</p>
                    </div>
                  {:else if overdueBooks.length === 0}
                    <div class="table-state-placeholder">
                      <span class="success-icon-badge">✓</span>
                      <p>System clean. No overdue files detected.</p>
                    </div>
                  {:else}
                    <table class="dashboard-table compact-table">
                      <thead>
                        <tr>
                          <th>Student ID</th>
                          <th>Title</th>
                          <th>Due Date</th>
                          <th>Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {#each overdueBooks.slice(0, 5) as book}
                          <tr>
                            <td class="font-mono">{book.id_no}</td>
                            <td class="table-cell-title" title={book.title}>{book.title}</td>
                            <td class="font-mono overdue-date">{book.due_date.split(' ')[0]}</td>
                            <td>
                              <button class="action-btn-small" on:click={() => {
                                applyTemplate(templates[0].text, book);
                              }}>
                                Select
                              </button>
                            </td>
                          </tr>
                        {/each}
                      </tbody>
                    </table>
                    {#if overdueBooks.length > 5}
                      <button class="view-more-records-btn font-mono" on:click={() => { activeTab = 'students-due'; fetchStudentsDue(true); }}>
                        + View {overdueBooks.length - 5} more overdue records in Registry
                      </button>
                    {/if}
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        <!-- BORROWERS REGISTRY TAB -->
        {#if activeTab === 'students-due'}
          <div class="explorer-container animate-fade">
            <!-- Filter box -->
            <div class="glass-card filter-card">
              <div class="filter-controls-grid">
                <!-- Search Box -->
                <div class="cyber-input-group no-margin">
                  <label for="filter-search">Search ID / Name</label>
                  <input
                    id="filter-search"
                    type="text"
                    bind:value={filterSearchQuery}
                    placeholder="Search by name or ID..."
                    on:input={() => fetchStudentsDue(true)}
                  />
                </div>

                <!-- Library Department -->
                <div class="cyber-input-group no-margin">
                  <label for="filter-dept">Library Department</label>
                  <select id="filter-dept" bind:value={filterDepartment} on:change={() => fetchStudentsDue(true)}>
                    <option value="">All Departments</option>
                    {#each filterDepartments as dept}
                      <option value={dept}>{dept}</option>
                    {/each}
                  </select>
                </div>

                <!-- Borrower Category -->
                <div class="cyber-input-group no-margin">
                  <label for="filter-cat">Borrower Category</label>
                  <select id="filter-cat" bind:value={filterCategory} on:change={() => fetchStudentsDue(true)}>
                    <option value="">All Categories</option>
                    {#each filterCategories as cat}
                      <option value={cat}>{cat}</option>
                    {/each}
                  </select>
                </div>

                <!-- Year of Study -->
                <div class="cyber-input-group no-margin">
                  <label for="filter-year">Year of Study/Join</label>
                  <input
                    id="filter-year"
                    type="text"
                    bind:value={filterStudyYear}
                    placeholder="e.g. 2024"
                    on:input={() => fetchStudentsDue(true)}
                  />
                </div>

                <!-- Gender -->
                <div class="cyber-input-group no-margin">
                  <label for="filter-gender">Gender</label>
                  <select id="filter-gender" bind:value={filterGender} on:change={() => fetchStudentsDue(true)}>
                    <option value="All">All Genders</option>
                    <option value="M">Male</option>
                    <option value="F">Female</option>
                  </select>
                </div>

                <!-- Checkbox -->
                <div class="checkbox-container" style="align-self: center; margin-top: 1rem;">
                  <label class="glow-checkbox">
                    <input type="checkbox" bind:checked={filterOverdueOnly} on:change={() => fetchStudentsDue(true)} />
                    <span class="checkbox-visual"></span>
                    <span class="checkbox-label">Filter Overdue Only</span>
                  </label>
                </div>
              </div>

              <!-- Toggle Chips for Designation -->
              <div class="cyber-input-group" style="margin-top: 1.2rem; margin-bottom: 0;">
                <label>Class/Designation (Toggle to select)</label>
                <div class="class-chips-container">
                  {#each availableClasses as c}
                    <button
                      type="button"
                      class="class-chip"
                      class:selected={filterClasses.includes(c)}
                      on:click={() => toggleFilterClass(c)}
                    >
                      {c}
                    </button>
                  {/each}
                </div>
              </div>
            </div>

            <!-- Big Table Card -->
            <div class="glass-card panel-card table-panel-card">
              <div class="panel-header-row">
                <div>
                  <h3>Borrowing Registry Directory</h3>
                  <p class="panel-subtitle">Audited book issues, return operations, and manual student warning channels.</p>
                </div>
                
                <!-- Pagination -->
                <div class="pagination-controls font-mono">
                  <button class="page-btn" on:click={() => { studentsDueOffset = Math.max(0, studentsDueOffset - studentsDueLimit); fetchStudentsDue(); }} disabled={studentsDueOffset === 0 || isLoadingStudentsDue}>
                    Prev
                  </button>
                  <span class="page-indicator">Page {Math.floor(studentsDueOffset / studentsDueLimit) + 1} of {Math.ceil(studentsDueTotal / studentsDueLimit) || 1}</span>
                  <button class="page-btn" on:click={() => { if (studentsDueOffset + studentsDueLimit < studentsDueTotal) { studentsDueOffset += studentsDueLimit; fetchStudentsDue(); } }} disabled={studentsDueOffset + studentsDueLimit >= studentsDueTotal || isLoadingStudentsDue}>
                    Next
                  </button>
                </div>
              </div>

              <div class="table-container">
                {#if isLoadingStudentsDue && studentsDue.length === 0}
                  <div class="table-state-placeholder">
                    <div class="spinner-small"></div>
                    <p>Loading database registry entries...</p>
                  </div>
                {:else if studentsDue.length === 0}
                  <div class="table-state-placeholder">
                    <p>No transactions match the active search criteria.</p>
                  </div>
                {:else}
                  <table class="dashboard-table full-table">
                    <thead>
                      <tr>
                        <th class="sortable-header" on:click={() => handleSort('id_no')}>Student ID ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('student_name')}>Name ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('student_class')}>Class ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('department')}>Dept ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('category')}>Category ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('acc_no')}>Acc No ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('title')}>Book Title ↕</th>
                        <th class="sortable-header" on:click={() => handleSort('due_date')}>Due Date ↕</th>
                        <th>Status</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {#each studentsDue as student}
                        <tr class={student.days_overdue > 0 ? 'row-overdue-alert' : ''}>
                          <td class="font-mono">{student.id_no}</td>
                          <td class="font-semibold">{student.student_name}</td>
                          <td>{student.student_class}</td>
                          <td>{student.department || '-'}</td>
                          <td>{student.category || '-'}</td>
                          <td class="font-mono">{student.acc_no}</td>
                          <td class="table-cell-title-long" title={student.title}>{student.title}</td>
                          <td class="font-mono">{student.due_date.split(' ')[0]}</td>
                          <td>
                            {#if student.days_overdue > 0}
                              <span class="status-badge status-badge-danger">{student.days_overdue} days late</span>
                            {:else}
                              <span class="status-badge status-badge-success">On Time</span>
                            {/if}
                          </td>
                          <td>
                            <div class="row-actions">
                              {#if student.phone}
                                <button class="row-btn btn-notify" on:click={() => notifyStudent(student)}>
                                  Alert
                                </button>
                              {:else}
                                <span class="no-contact-label font-mono">No Phone</span>
                              {/if}
                              <button class="row-btn btn-return" on:click={() => markAsReturned(student)}>
                                Return
                              </button>
                            </div>
                          </td>
                        </tr>
                      {/each}
                    </tbody>
                  </table>
                {/if}
              </div>
            </div>
          </div>
        {/if}

        <!-- GATEWAY SYNC TAB -->
        {#if activeTab === 'whatsapp'}
          <div class="gateway-hub animate-fade">
            {#if connStatus === "checking"}
              <div class="gateway-status-checking glass-card animate-fade">
                <div class="spinner-circle"></div>
                <h3>Synchronizing Active Gateway Nodes</h3>
                <p class="muted-text">Pinging Evolution API docker server instance on Azure host (20.6.122.244)...</p>
              </div>
            {:else}
              <div class="gateway-grid-layout">
                <!-- Session Manager -->
                <div class="glass-card panel-card">
                  <div class="panel-header">
                    <h3>Session Instances Provisioner</h3>
                    <p class="panel-subtitle">Manage system instances and configure new WhatsApp session tokens.</p>
                  </div>
                  
                  <div class="panel-body">
                    <div class="cyber-input-group">
                      <label for="instance-select">Active WhatsApp Session Node</label>
                      <select id="instance-select" bind:value={selectedInstance} on:change={handleInstanceChange}>
                        <option value="">-- Choose Session Instance --</option>
                        {#each instances as inst}
                          <option value={inst.name}>{inst.name} ({inst.connectionStatus})</option>
                        {/each}
                      </select>
                    </div>

                    <div class="cyber-divider font-mono"><span>PROVISION NEW ACCESS CHANNEL</span></div>

                    <div class="cyber-input-group">
                      <label for="new-instance-name">New Access Session Name</label>
                      <div class="inline-input-action">
                        <input id="new-instance-name" type="text" bind:value={newInstanceName} placeholder="Instance code (e.g. halo)" />
                        <button class="action-btn-primary inline-action-btn" disabled={isCreatingInstance} on:click={handleCreateInstance}>
                          {isCreatingInstance ? 'Wait...' : 'Create'}
                        </button>
                      </div>
                    </div>

                    {#if selectedInstance}
                      <div class="instance-controls-console font-mono animate-fade">
                        <span class="section-tag-sub">SESSION CONTROLS [ID: {selectedInstance}]</span>
                        <div class="instance-control-buttons">
                          <button class="cyber-console-btn" on:click={checkSetup}>Ping Status</button>
                          <button class="cyber-console-btn btn-danger-console" on:click={forceReset}>Log Out Session</button>
                          <button class="cyber-console-btn btn-danger-console" on:click={handleDeleteInstance}>Destroy Instance</button>
                        </div>
                      </div>
                    {/if}
                  </div>
                </div>

                <!-- QR Linking terminal -->
                <div class="glass-card panel-card authentication-card">
                  <div class="panel-header">
                    <h3>Device Authn Gateway</h3>
                    <p class="panel-subtitle">Establish active link between Evolution API and Whatsapp device.</p>
                  </div>

                  <div class="panel-body">
                    {#if selectedInstance}
                      <div class="auth-sections animate-fade">
                        <!-- Scan QR -->
                        <div class="auth-method qr-auth-method">
                          <h4 class="font-mono">METHOD 1: SECURE QR TOKEN</h4>
                          <div class="qr-code-frame">
                            <div class="qr-scan-line"></div>
                            {#if qrCode}
                              <img src={qrCode} alt="WhatsApp QR Access Token" />
                            {:else}
                              <div class="qr-loading-container">
                                <div class="spinner-circle"></div>
                                <p>Awaiting QR stream from VM...</p>
                              </div>
                            {/if}
                          </div>
                          <p class="frame-instruction font-mono">Open WhatsApp -> Linked Devices -> Scan QR Code</p>
                        </div>

                        <!-- Phone pairing -->
                        <div class="auth-method pairing-auth-method">
                          <h4 class="font-mono">METHOD 2: PAIRING CODE</h4>
                          <div class="cyber-input-group">
                            <label for="phone-linker">Target Phone Number</label>
                            <input id="phone-linker" type="text" bind:value={phoneNumber} placeholder="91XXXXXXXXXX" />
                          </div>
                          <button class="action-btn-primary pair-btn-dispatch" disabled={isPairingLoading} on:click={() => fetchConnData(phoneNumber)}>
                            {isPairingLoading ? 'Requesting key...' : 'Request Pairing Code'}
                          </button>

                          {#if pairingCode}
                            <div class="pairing-code-terminal animate-fade">
                              <span class="terminal-label font-mono">PAIRING AUTH CODE</span>
                              <div class="terminal-code font-mono">{pairingCode}</div>
                            </div>
                          {/if}
                        </div>
                      </div>
                    {:else}
                      <div class="gateway-unselected-placeholder">
                        <span class="unselected-icon-glow">🔌</span>
                        <h4>No Session Hooked</h4>
                        <p>Select or create an API session node in the Provisioner panel to display authentication streams.</p>
                      </div>
                    {/if}
                  </div>
                </div>
              </div>
            {/if}
          </div>
        {/if}

        <!-- SYSTEM LOGS TAB -->
        {#if activeTab === 'logs'}
          <div class="logs-container animate-fade">
            <div class="glass-card panel-card logs-panel">
              <div class="panel-header-row">
                <div>
                  <h3>Realtime Dashboard Event Stream</h3>
                  <p class="panel-subtitle">Internal console records, WhatsApp API delivery logs, and database sync telemetry.</p>
                </div>
                <button class="log-clear-btn font-mono" on:click={() => { systemLogs = []; logEvent("Event stream console cleared", "warning"); }}>
                  [CLEAR LOGS]
                </button>
              </div>

              <div class="panel-body console-log-body">
                <div class="log-console font-mono">
                  {#each systemLogs as log}
                    <div class="log-line log-{log.type}">
                      <span class="log-timestamp">[{log.time}]</span>
                      <span class="log-type-tag">[{log.type.toUpperCase()}]</span>
                      <span class="log-message">{log.msg}</span>
                    </div>
                  {:else}
                    <div class="log-line log-info">
                      <span class="log-timestamp">[{new Date().toLocaleTimeString()}]</span>
                      <span class="log-type-tag">[INFO]</span>
                      <span class="log-message">Console logger online. Waiting for transactions...</span>
                    </div>
                  {/each}
                </div>
              </div>
            </div>
          </div>
        {/if}

        <!-- MASTER USER SEARCH TAB -->
        {#if activeTab === 'master-search'}
          <div class="master-search-container animate-fade">
            <div class="glass-card panel-card search-inputs-card">
              <div class="panel-header">
                <h3>Master Directory Query</h3>
                <p class="panel-subtitle">Search members by roll number, register number, department, batch, phone, or name.</p>
              </div>

              <div class="panel-body">
                <div class="search-inputs-grid">
                  <div class="cyber-input-group">
                    <label for="ms-roll">Roll Number (ID)</label>
                    <input id="ms-roll" type="text" bind:value={masterSearchRoll} placeholder="e.g. 2K24ECE001" on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>

                  <div class="cyber-input-group">
                    <label for="ms-reg">Register Number</label>
                    <input id="ms-reg" type="text" bind:value={masterSearchReg} placeholder="e.g. 911524..." on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>

                  <div class="cyber-input-group">
                    <label for="ms-name">Full Name</label>
                    <input id="ms-name" type="text" bind:value={masterSearchName} placeholder="e.g. BARATH S" on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>

                  <div class="cyber-input-group">
                    <label for="ms-dept">Department Code</label>
                    <input id="ms-dept" type="text" bind:value={masterSearchDept} placeholder="e.g. ECE" on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>

                  <div class="cyber-input-group">
                    <label for="ms-batch">Batch Year</label>
                    <input id="ms-batch" type="text" bind:value={masterSearchBatch} placeholder="e.g. 2K24" on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>

                  <div class="cyber-input-group">
                    <label for="ms-phone">Phone Number</label>
                    <input id="ms-phone" type="text" bind:value={masterSearchPhone} placeholder="e.g. 912356..." on:keydown={(e) => e.key === 'Enter' && handleMasterSearch()} />
                  </div>
                </div>

                <div class="search-actions-row">
                  <button class="action-btn-secondary clear-search-btn font-mono" on:click={resetMasterSearch}>
                    Reset Fields
                  </button>
                  <button class="action-btn-primary execute-search-btn" on:click={handleMasterSearch} disabled={isMasterSearching}>
                    {isMasterSearching ? 'Searching Database...' : '🔍 Execute Master Query'}
                  </button>
                </div>
              </div>
            </div>

            <div class="search-split-layout">
              <!-- Results List -->
              <div class="glass-card panel-card results-list-card">
                <div class="panel-header-row">
                  <div>
                    <h3>Matched Members ({masterSearchResults.length})</h3>
                    <p class="panel-subtitle">Click a record to pull full metadata & transaction history.</p>
                  </div>
                </div>

                <div class="panel-body results-list-body">
                  {#if isMasterSearching && masterSearchResults.length === 0}
                    <div class="table-state-placeholder">
                      <div class="spinner-small"></div>
                      <p>Running index lookup queries...</p>
                    </div>
                  {:else if masterSearchResults.length === 0}
                    <div class="table-state-placeholder font-mono">
                      <span>[NO ACTIVE FILTERS]</span>
                      <p>Specify filters above and hit Execute.</p>
                    </div>
                  {:else}
                    <div class="results-scrollable">
                      {#each masterSearchResults as member}
                        <!-- svelte-ignore a11y-click-events-have-key-events -->
                        <!-- svelte-ignore a11y-no-static-element-interactions -->
                        <div class="member-result-item" class:selected={selectedMemberDetail?.id_no === member.id_no} on:click={() => selectMember(member)}>
                          <div class="member-result-avatar">
                            {member.name.charAt(0)}
                          </div>
                          <div class="member-result-info">
                            <span class="member-res-name font-semibold">{member.name}</span>
                            <span class="member-res-sub font-mono">{member.id_no} · {member.dept_name || 'N/A'}</span>
                          </div>
                          <span class="member-res-class-tag font-mono">{member.class}</span>
                        </div>
                      {/each}
                    </div>
                  {/if}
                </div>
              </div>

              <!-- Profile Details -->
              <div class="glass-card panel-card profile-details-card">
                <div class="panel-header">
                  <h3>Member Deep Profile</h3>
                  <p class="panel-subtitle">Detailed metadata and current transaction ledger.</p>
                </div>

                <div class="panel-body profile-details-body">
                  {#if selectedMemberDetail}
                    <div class="profile-header-meta">
                      <div class="profile-avatar-large">
                        {selectedMemberDetail.name.charAt(0)}
                      </div>
                      <div class="profile-title-block">
                        <h4>{selectedMemberDetail.name}</h4>
                        <span class="profile-status-badge {selectedMemberDetail.active_member === 1 ? 'status-active' : 'status-inactive'} font-mono">
                          {selectedMemberDetail.active_member === 1 ? 'ACTIVE MEMBERSHIP' : 'SUSPENDED'}
                        </span>
                      </div>
                    </div>

                    <div class="profile-info-grid font-mono">
                      <div class="profile-info-row">
                        <span class="info-label">Roll Number:</span>
                        <span class="info-val">{selectedMemberDetail.id_no}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Register No:</span>
                        <span class="info-val">{selectedMemberDetail.reg_no || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Class Category:</span>
                        <span class="info-val">{selectedMemberDetail.class} / {selectedMemberDetail.cat_name || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Department:</span>
                        <span class="info-val">{selectedMemberDetail.dept_name || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Study Year:</span>
                        <span class="info-val">{selectedMemberDetail.study_year || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Mobile Contact:</span>
                        <span class="info-val">{selectedMemberDetail.phone || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Email Address:</span>
                        <span class="info-val">{selectedMemberDetail.email || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Gender / DOB:</span>
                        <span class="info-val">{selectedMemberDetail.gender || 'N/A'} / {selectedMemberDetail.dob || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Blood Group:</span>
                        <span class="info-val">{selectedMemberDetail.blood_group || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Parent/Guardian:</span>
                        <span class="info-val">{selectedMemberDetail.parent || 'N/A'}</span>
                      </div>
                      <div class="profile-info-row">
                        <span class="info-label">Admission No:</span>
                        <span class="info-val">{selectedMemberDetail.admn_no || 'N/A'}</span>
                      </div>
                    </div>

                    <!-- Borrows Ledger -->
                    <div class="borrows-ledger-section">
                      <h5 class="font-mono">ACTIVE LOAN RECORDS ({selectedMemberDetail.active_borrows.length})</h5>
                      {#if selectedMemberDetail.active_borrows.length === 0}
                        <div class="ledger-empty font-mono">
                          No currently borrowed books registered.
                        </div>
                      {:else}
                        <div class="ledger-list">
                          {#each selectedMemberDetail.active_borrows as b}
                            <div class="ledger-item" class:overdue-ledger-item={b.days_overdue > 0}>
                              <div class="ledger-book-details">
                                <span class="ledger-title font-semibold">{b.title}</span>
                                <span class="ledger-author font-mono">Acc No: {b.acc_no} · By {b.author}</span>
                              </div>
                              <div class="ledger-date-info text-right">
                                <span class="ledger-due font-mono {b.days_overdue > 0 ? 'overdue-date' : ''}">DUE: {b.due_date.split(' ')[0]}</span>
                                {#if b.days_overdue > 0}
                                  <span class="ledger-overdue-tag font-mono">{b.days_overdue} days overdue</span>
                                {/if}
                              </div>
                            </div>
                          {/each}
                        </div>
                      {/if}
                    </div>
                  {:else}
                    <div class="profile-unselected-state font-mono">
                      [AWAITING SELECTION]
                      <p style="margin-top: 0.5rem; font-size: 0.72rem; color: var(--muted);">Select a member from the results list to view complete profile and active transaction logs.</p>
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        <!-- DUE LIST REPORTS TAB -->
        {#if activeTab === 'reports'}
          <div class="master-search-container animate-fade no-print" style="margin-bottom: 2rem;">
            <div class="glass-card panel-card search-inputs-card" style="width: 100%; max-width: 100%;">
              <div class="panel-header">
                <h3>Members Due List Reports</h3>
                <p class="panel-subtitle">Generate official borrower due registers and fine audit reports.</p>
              </div>

              <div class="panel-body">
                <div class="search-inputs-grid" style="grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));">
                  <div class="cyber-input-group">
                    <label for="rep-dept">Department</label>
                    <select id="rep-dept" class="cyber-select" bind:value={reportDept}>
                      <option value="All Departments">All Departments</option>
                      {#each filterDepartments as dept}
                        <option value={dept}>{dept}</option>
                      {/each}
                    </select>
                  </div>

                  <div class="cyber-input-group">
                    <label for="rep-category">Borrower Category</label>
                    <select id="rep-category" class="cyber-select" bind:value={reportCategory}>
                      <option value="All Categories">All Categories</option>
                      {#each filterCategories as cat}
                        <option value={cat}>{cat}</option>
                      {/each}
                    </select>
                  </div>

                  <div class="cyber-input-group">
                    <label>Class/Designation (Toggle to select)</label>
                    <div class="class-chips-container">
                      {#each availableClasses as c}
                        <button
                          type="button"
                          class="class-chip"
                          class:selected={selectedClasses.includes(c)}
                          on:click={() => toggleClass(c)}
                        >
                          {c}
                        </button>
                      {/each}
                    </div>
                  </div>

                  <div class="cyber-input-group">
                    <label for="rep-year">Year of Study/Join</label>
                    <input id="rep-year" class="cyber-text-input" type="text" bind:value={reportStudyYear} placeholder="e.g. 2024" />
                  </div>

                  <div class="cyber-input-group">
                    <label for="rep-gender">Gender</label>
                    <select id="rep-gender" class="cyber-select" bind:value={reportGender}>
                      <option value="All">All Genders</option>
                      <option value="M">Male</option>
                      <option value="F">Female</option>
                    </select>
                  </div>

                  <div class="cyber-input-group">
                    <label for="rep-id-pattern">ID Pattern (Roll Prefix)</label>
                    <input id="rep-id-pattern" class="cyber-text-input" type="text" bind:value={reportIdPattern} placeholder="e.g. 2K24ECE" />
                  </div>

                  <div class="cyber-input-group">
                    <label>ID Match Options</label>
                    <div style="display: flex; gap: 1rem; margin-top: 0.5rem; flex-wrap: wrap;">
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportMatchType} value="left" /> Left</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportMatchType} value="exact" /> Exact</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportMatchType} value="like" /> Like</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportMatchType} value="right" /> Right</label>
                    </div>
                  </div>

                  <div class="cyber-input-group">
                    <label>Membership Status</label>
                    <div style="display: flex; gap: 1rem; margin-top: 0.5rem; flex-wrap: wrap;">
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportActiveStatus} value="active" /> Active</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportActiveStatus} value="old" /> Passed Out</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportActiveStatus} value="both" /> Both</label>
                    </div>
                  </div>

                  <div class="cyber-input-group">
                    <label for="rep-fine-rate">Daily Fine Rate (Rs)</label>
                    <input id="rep-fine-rate" class="cyber-text-input" type="number" step="0.05" bind:value={reportFineRate} placeholder="0.50" />
                  </div>

                  <div class="cyber-input-group">
                    <label>Output Format</label>
                    <div style="display: flex; gap: 1rem; margin-top: 0.5rem; flex-wrap: wrap;">
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportPrintOption} value="window" /> To Window</label>
                      <label class="radio-label font-mono"><input type="radio" bind:group={reportPrintOption} value="pdf" /> To PDF / Printer</label>
                    </div>
                  </div>
                </div>

                <div class="search-actions-row">
                  <button class="action-btn-secondary clear-search-btn font-mono" on:click={resetReports}>
                    Clear Options
                  </button>
                  <button class="action-btn-primary execute-search-btn" on:click={handleGenerateReport} disabled={isGeneratingReport}>
                    {isGeneratingReport ? 'Compiling Report...' : '📊 Compile Due List'}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- REPORT RESULTS / PREVIEW WINDOW -->
          {#if reportResults}
            <div class="report-preview-outer-wrap animate-fade">
              <div class="report-action-header no-print" style="margin-bottom: 1rem; display: flex; justify-content: space-between; align-items: center;">
                <h4 class="font-mono text-accent">REPORT CONTAINER PREVIEW ({reportPrintOption === 'pdf' ? 'PRINT DIALOG TRIGGERED' : 'WINDOW VIEW'})</h4>
                <button class="action-btn-primary" on:click={() => window.print()}>
                  🖨️ Direct Print / Save PDF
                </button>
              </div>

              <div class="report-print-area report-preview-paper-card">
                <div class="report-header text-center">
                  <h2 class="report-college-title">Knowledge Institute of Technology</h2>
                  <h3 class="report-college-location">Salem - 637 504</h3>
                  <div class="report-title-line">
                    <h4 class="report-title-text font-bold uppercase">{reportResults.report_title}</h4>
                  </div>
                  <div class="report-meta-row font-mono">
                    <span>REPORT DATE: {reportResults.generated_date}</span>
                  </div>
                </div>

                <div class="report-body">
                  {#if reportResults.members.length === 0}
                    <div class="report-empty-state font-mono text-center">
                      -- NO DUE RECORDS MATCHED SELECTED FILTER CRITERIA --
                    </div>
                  {:else}
                    {#each reportResults.members as member}
                      <div class="report-member-group">
                        <div class="report-member-header font-bold font-mono">
                          ID No : {member.id_no} &nbsp;&nbsp;&nbsp;&nbsp; Dept : {member.dept_name} &nbsp;&nbsp;&nbsp;&nbsp; {member.name}
                        </div>

                        <table class="report-data-table font-mono">
                          <thead>
                            <tr class="table-header-underline">
                              <th align="left">Library</th>
                              <th align="left">Particular No.</th>
                              <th align="left" style="width: 45%;">Particular Detail</th>
                              <th align="left">Due date</th>
                              <th align="right">Overdue Days</th>
                              <th align="right">Over</th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr class="material-type-row">
                              <td colspan="6" class="font-semibold" style="padding: 0.35rem 0; font-size: 0.85rem; color: #555;">Material Type : Book</td>
                            </tr>
                            {#each member.books as book}
                              <tr class="book-data-row">
                                <td align="left">{book.library}</td>
                                <td align="left">{book.acc_no}</td>
                                <td align="left" class="detail-cell">{book.title} - {book.author}</td>
                                <td align="left">
                                  {(() => {
                                    const parts = book.due_date.split(' ')[0].split('-');
                                    return parts.length === 3 ? `${parts[2]}/${parts[1]}/${parts[0]}` : book.due_date;
                                  })()}
                                </td>
                                <td align="right">{book.overdue_days || '0'}</td>
                                <td align="right">{book.overdue_amount.toFixed(2)}</td>
                              </tr>
                            {/each}
                          </tbody>
                        </table>

                        <div class="report-member-footer font-mono text-right">
                          <div class="book-subtotal">Book &nbsp;&nbsp;&nbsp;&nbsp; <span class="subtotal-val font-semibold">{member.total_fine.toFixed(2)}</span></div>
                          <div class="paid-by-line">Amount to be paid by {member.id_no} &nbsp;&nbsp;&nbsp;&nbsp; <span class="subtotal-val font-bold">{member.total_fine.toFixed(2)}</span></div>
                        </div>
                      </div>
                    {/each}

                    <div class="report-grand-footer font-mono text-right">
                      <span class="grand-total-label font-bold">Total Amount to be Collected :</span>
                      <span class="grand-total-val font-bold border-double-bottom">{reportResults.grand_total.toFixed(2)}</span>
                    </div>
                  {/if}
                </div>
                
                <div class="report-page-number-footer font-mono text-center print-only-block" style="margin-top: 2rem; font-size: 0.8rem;">
                  1
                </div>
              </div>
            </div>
          {/if}
        {/if}

        {#if activeTab === 'add-member'}
          <AddMemberView />
        {/if}

        {#if activeTab === 'add-book'}
          <AddBookView />
        {/if}

        {#if activeTab === 'settings'}
          <div class="panel-card glass" style="margin-top: 1.5rem; padding: 1.5rem; background: var(--card); border: 1px solid var(--border); border-radius: 12px; box-shadow: 0 8px 30px rgba(0,0,0,0.2);">
            <div class="panel-header" style="border-bottom: 1px solid var(--border); padding-bottom: 0.8rem; margin-bottom: 1.5rem;">
              <h2 class="panel-title" style="font-family: 'DM Serif Display', serif; font-size: 1.35rem; color: var(--accent);">System Settings</h2>
              <p class="panel-subtitle" style="font-size: 0.8rem; color: var(--muted); margin-top: 0.2rem;">Configure application parameters and settings globally.</p>
            </div>
            
            <div class="settings-group" style="max-width: 500px;">
              <div style="margin-bottom: 1.5rem;">
                <label style="display: block; font-size: 0.82rem; font-weight: 500; margin-bottom: 0.5rem; color: var(--accent);">About Page GitHub Developer Usernames</label>
                
                <div style="display: flex; gap: 0.5rem; margin-bottom: 0.8rem;">
                  <input 
                    type="text" 
                    bind:value={newUsernameInput} 
                    placeholder="Type GitHub username..." 
                    on:keydown={(e) => e.key === 'Enter' && (e.preventDefault(), addUsername())}
                    style="flex-grow: 1; padding: 0.65rem 0.75rem; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); outline: none; transition: border-color 0.2s;"
                  />
                  <button 
                    type="button"
                    on:click={addUsername}
                    style="padding: 0.65rem 1rem; background: var(--surface); border: 1px solid var(--border); color: var(--accent); border-radius: 6px; cursor: pointer; transition: all 0.2s;"
                  >
                    + Add
                  </button>
                </div>

                <div class="usernames-list" style="display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 0.8rem; padding: 0.6rem; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; min-height: 46px; align-items: center;">
                  {#if devUsernames.length === 0}
                    <span style="font-size: 0.75rem; color: var(--muted); padding-left: 0.5rem;">No usernames added yet. Default (AADHIISHVAR) will be used.</span>
                  {:else}
                    {#each devUsernames as name, i}
                      <span class="user-tag" style="display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.25rem 0.6rem; background: rgba(200, 169, 110, 0.1); border: 1px solid var(--accent); color: var(--text); border-radius: 20px; font-size: 0.78rem;">
                        {name}
                        <button 
                          type="button" 
                          on:click={() => removeUsername(i)} 
                          style="background: none; border: none; color: var(--accent); cursor: pointer; font-size: 0.95rem; font-weight: bold; padding: 0; margin-left: 0.1rem; line-height: 1;"
                          aria-label="Remove username"
                        >
                          &times;
                        </button>
                      </span>
                    {/each}
                  {/if}
                </div>
                
                <span class="hint" style="display: block; margin-top: 0.4rem; color: var(--muted); font-size: 0.72rem; line-height: 1.35;">Add GitHub usernames of contributors. Their avatars, bio, and profiles will be loaded dynamically on the About page.</span>
              </div>
              
              {#if settingsSaveStatus}
                <div style="margin-bottom: 1.5rem; font-size: 0.82rem; padding: 0.6rem; border-radius: 6px; border: 1px solid {settingsSaveStatus.success ? 'var(--success)' : 'var(--danger)'}; color: {settingsSaveStatus.success ? 'var(--success)' : 'var(--danger)'}; background: rgba(0,0,0,0.15);">
                  {settingsSaveStatus.msg}
                </div>
              {/if}

              <button 
                class="primary-btn" 
                on:click={saveSettings} 
                disabled={isSavingSettings}
                style="padding: 0.65rem 1.25rem; font-weight: bold; background: var(--accent); color: #1a1409; border: none; border-radius: 6px; cursor: pointer; transition: opacity 0.2s, transform 0.1s;"
              >
                {isSavingSettings ? "Saving..." : "Save Settings"}
              </button>
            </div>
          </div>
        {/if}
      </main>
    </div>
  {/if}
</div>

<style>
  /* --- CYBER ACCESS CARD STYLES --- */
  .login-wrapper {
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 4rem 1rem;
    position: relative;
    width: 100%;
    min-height: 70vh;
  }
  .login-backdrop-glow {
    position: absolute;
    width: 350px;
    height: 350px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(200, 169, 110, 0.08) 0%, transparent 70%);
    filter: blur(40px);
    pointer-events: none;
    z-index: 0;
  }
  .login-box {
    position: relative;
    background: rgba(20, 20, 23, 0.75);
    backdrop-filter: blur(20px);
    border: 1px solid rgba(255, 255, 255, 0.04);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.03);
    border-radius: 20px;
    padding: 3rem 2.8rem;
    width: 100%;
    max-width: 460px;
    z-index: 1;
    overflow: hidden;
  }
  .login-header-glow {
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
    background: linear-gradient(90deg, var(--accent) 0%, var(--accent2) 100%);
    box-shadow: 0 2px 20px rgba(200, 169, 110, 0.4);
  }
  .cyber-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.65rem;
    color: var(--accent);
    letter-spacing: 0.15em;
    border: 1px solid rgba(200, 169, 110, 0.25);
    background: rgba(200, 169, 110, 0.04);
    padding: 0.3rem 0.75rem;
    border-radius: 30px;
    margin-bottom: 1.8rem;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
  }
  .login-box h2 {
    font-family: 'DM Serif Display', serif;
    font-size: 2.1rem;
    color: var(--text);
    font-weight: 400;
    margin-bottom: 0.6rem;
  }
  .login-desc {
    font-size: 0.85rem;
    color: var(--muted);
    line-height: 1.5;
    margin-bottom: 2.2rem;
  }
  .cyber-input-group {
    margin-bottom: 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    width: 100%;
  }
  .cyber-input-group label {
    font-family: 'DM Mono', monospace;
    font-size: 0.7rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .cyber-input-wrap {
    position: relative;
    width: 100%;
  }
  .cyber-input-icon {
    position: absolute;
    left: 1.1rem;
    top: 50%;
    transform: translateY(-50%);
    color: var(--accent);
    opacity: 0.75;
    display: flex;
    align-items: center;
    pointer-events: none;
  }
  .cyber-input-wrap input {
    width: 100%;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 0.85rem 1rem 0.85rem 2.8rem;
    color: var(--text);
    font-size: 0.92rem;
    outline: none;
    transition: all 0.25s ease;
  }
  .cyber-input-wrap input:focus {
    border-color: var(--accent);
    background: rgba(0, 0, 0, 0.4);
    box-shadow: 0 0 15px rgba(200, 169, 110, 0.12);
  }
  .cyber-error-box {
    display: flex;
    align-items: center;
    gap: 0.7rem;
    background: rgba(224, 108, 108, 0.08);
    border: 1px solid rgba(224, 108, 108, 0.25);
    padding: 0.85rem 1.1rem;
    border-radius: 10px;
    margin-bottom: 1.8rem;
    color: var(--danger);
    font-size: 0.82rem;
  }
  .error-svg-icon {
    flex-shrink: 0;
  }
  .cyber-login-btn {
    width: 100%;
    background: linear-gradient(135deg, var(--accent) 0%, #b8995e 100%);
    color: #1a1409;
    border: none;
    padding: 1rem;
    border-radius: 10px;
    font-weight: 600;
    font-family: 'DM Sans', sans-serif;
    font-size: 0.95rem;
    cursor: pointer;
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 0.6rem;
    box-shadow: 0 8px 20px rgba(200, 169, 110, 0.18);
    transition: all 0.25s ease;
  }
  .cyber-login-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 12px 25px rgba(200, 169, 110, 0.3);
  }
  .cyber-login-btn svg {
    transition: transform 0.2s ease;
  }
  .cyber-login-btn:hover svg {
    transform: translateX(4px);
  }

  /* --- FULL DASHBOARD SYSTEM LAYOUT --- */
  .dashboard-container {
    display: grid;
    grid-template-columns: 265px 1fr;
    min-height: calc(100vh - 57px);
    background: rgba(20, 20, 23, 0.5);
    backdrop-filter: blur(25px);
    border: none;
    border-radius: 0;
    overflow: hidden;
    margin: 0;
  }

  /* SIDEBAR STYLINGS */
  .dashboard-sidebar {
    background: rgba(16, 16, 19, 0.85);
    border-right: 1px solid var(--border);
    padding: 2.2rem 1.4rem;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    z-index: 10;
  }
  .sidebar-brand {
    display: flex;
    flex-direction: column;
    gap: 0.8rem;
    margin-bottom: 2.8rem;
    padding-bottom: 1.5rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
  }
  .brand-logo {
    display: flex;
    align-items: center;
    gap: 0.65rem;
    font-family: 'DM Serif Display', serif;
    font-size: 1.3rem;
    color: var(--text);
  }
  .system-status-indicator {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    font-size: 0.65rem;
    letter-spacing: 0.08em;
    padding: 0.25rem 0.6rem;
    border-radius: 4px;
    width: fit-content;
  }
  .status-online {
    background: rgba(78, 173, 133, 0.08);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.2);
  }
  .status-offline {
    background: rgba(200, 169, 110, 0.08);
    color: var(--accent);
    border: 1px solid rgba(200, 169, 110, 0.2);
  }
  .status-pulse-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    position: relative;
  }
  .status-online .status-pulse-dot { background-color: var(--success); }
  .status-offline .status-pulse-dot { background-color: var(--accent); }
  .status-pulse-dot::after {
    content: '';
    position: absolute;
    width: 100%; height: 100%;
    border-radius: 50%;
    left: 0; top: 0;
    animation: statusPulse 2s infinite ease-out;
  }
  .status-online .status-pulse-dot::after { background-color: var(--success); }
  .status-offline .status-pulse-dot::after { background-color: var(--accent); }
  
  @keyframes statusPulse {
    0% { transform: scale(1); opacity: 0.8; }
    100% { transform: scale(2.8); opacity: 0; }
  }

  .sidebar-nav {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    flex-grow: 1;
  }
  .nav-item {
    background: none;
    border: none;
    color: var(--muted);
    font-family: 'DM Sans', sans-serif;
    font-size: 0.88rem;
    font-weight: 500;
    padding: 0.8rem 1rem;
    border-radius: 10px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 0.8rem;
    text-align: left;
    width: 100%;
    position: relative;
    transition: all 0.25s ease;
  }
  .nav-item svg {
    opacity: 0.6;
    transition: all 0.2s ease;
  }
  .nav-item:hover {
    color: var(--text);
    background: rgba(255, 255, 255, 0.02);
  }
  .nav-item:hover svg {
    opacity: 0.9;
    color: var(--accent);
  }
  .nav-item.active {
    color: var(--accent);
    background: rgba(200, 169, 110, 0.06);
    box-shadow: inset 0 0 0 1px rgba(200, 169, 110, 0.15);
  }
  .nav-item.active::before {
    content: '';
    position: absolute;
    left: 0; top: 20%; bottom: 20%;
    width: 3px;
    background: var(--accent);
    border-radius: 0 4px 4px 0;
    box-shadow: 0 0 8px var(--accent);
  }
  .nav-item.active svg {
    opacity: 1;
    color: var(--accent);
  }
  .badge-count {
    background: rgba(124, 111, 205, 0.25);
    color: #b7abff;
    border: 1px solid rgba(124, 111, 205, 0.3);
    font-family: 'DM Mono', monospace;
    font-size: 0.65rem;
    padding: 0.1rem 0.45rem;
    border-radius: 20px;
    margin-left: auto;
  }

  .sidebar-footer {
    display: flex;
    flex-direction: column;
    gap: 1.2rem;
    padding-top: 1.5rem;
    border-top: 1px solid rgba(255, 255, 255, 0.03);
  }
  .admin-profile {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  .admin-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--accent2) 0%, #5d51ad 100%);
    color: var(--text);
    font-weight: 600;
    font-size: 0.82rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .admin-info {
    display: flex;
    flex-direction: column;
  }
  .admin-name {
    font-size: 0.82rem;
    color: var(--text);
    font-weight: 600;
  }
  .admin-role {
    font-size: 0.68rem;
    color: var(--muted);
  }
  .logout-btn {
    background: none;
    border: 1px solid rgba(224, 108, 108, 0.2);
    color: var(--danger);
    border-radius: 8px;
    font-family: 'DM Mono', monospace;
    font-size: 0.75rem;
    font-weight: 600;
    padding: 0.55rem;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    transition: all 0.2s ease;
  }
  .logout-btn:hover {
    background: rgba(224, 108, 108, 0.06);
    border-color: var(--danger);
  }

  /* WORKSPACE STYLINGS */
  .dashboard-workspace {
    padding: 2.2rem 1.5rem;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 1.8rem;
    background: rgba(13, 13, 15, 0.3);
  }
  .workspace-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-bottom: 1.2rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    background: none;
    backdrop-filter: none;
    position: static;
    padding: 0;
  }
  .breadcrumb {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.7rem;
    letter-spacing: 0.1em;
  }
  .bc-parent { color: var(--muted); }
  .bc-sep { color: var(--border); }
  .bc-active { color: var(--accent); font-weight: 600; }
  
  .header-actions {
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  .wa-status-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    font-size: 0.68rem;
    padding: 0.3rem 0.75rem;
    border-radius: 30px;
    font-weight: 500;
  }
  .badge-success {
    background: rgba(78, 173, 133, 0.08);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.15);
  }
  .badge-danger {
    background: rgba(224, 108, 108, 0.08);
    color: var(--danger);
    border: 1px solid rgba(224, 108, 108, 0.15);
  }
  .pulse-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    display: inline-block;
  }
  .pulse-green { background-color: var(--success); }
  .pulse-red { background-color: var(--danger); }
  .pulse-gold { background-color: var(--accent); }
  .header-refresh-btn {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border);
    color: var(--muted);
    border-radius: 8px;
    width: 32px; height: 32px;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .header-refresh-btn:hover {
    color: var(--accent);
    border-color: var(--accent);
    background: rgba(255,255,255,0.05);
  }

  /* ALERTS BANNER CSS */
  .alert-banner {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: rgba(200, 169, 110, 0.08);
    border: 1px dashed rgba(200, 169, 110, 0.25);
    border-radius: 12px;
    padding: 0.85rem 1.2rem;
  }
  .alert-content {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  .alert-icon {
    color: var(--accent);
    font-size: 1.1rem;
    line-height: 1;
  }
  .alert-content p {
    font-size: 0.82rem;
    color: var(--accent);
    margin: 0;
  }
  .alert-close-btn {
    background: none;
    border: none;
    color: var(--accent);
    font-size: 1.2rem;
    cursor: pointer;
    opacity: 0.6;
    transition: opacity 0.2s;
  }
  .alert-close-btn:hover { opacity: 1; }

  /* KPI STAT GRID CSS */
  .kpi-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 1.5rem;
  }
  .kpi-card {
    background: transparent;
    border: none;
    border-radius: 0;
    padding: 1.2rem 1.4rem;
    position: relative;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    min-height: 110px;
    transition: none;
    box-shadow: none;
  }
  .kpi-card:hover {
    transform: none;
    border-color: transparent;
    box-shadow: none;
  }
  .kpi-card::before {
    content: '';
    position: absolute;
    left: 0; top: 0; bottom: 0;
    width: 3px;
    background: var(--accent);
  }
  .kpi-card.kpi-success::before { background: var(--success); }
  .kpi-card.kpi-warning::before { background: var(--danger); }
  .kpi-card.kpi-purple::before { background: var(--accent2); }

  .kpi-card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .kpi-card-title {
    font-family: 'DM Mono', monospace;
    font-size: 0.65rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .kpi-card-icon {
    font-size: 1.1rem;
    opacity: 0.75;
  }
  .kpi-card-body {
    margin-top: 0.8rem;
    z-index: 2;
  }
  .kpi-card-value {
    font-family: 'DM Serif Display', serif;
    font-size: 1.8rem;
    color: var(--text);
    line-height: 1.1;
  }
  .kpi-card-meta {
    font-size: 0.72rem;
    color: var(--muted);
    margin-top: 0.3rem;
  }
  .kpi-card-meta strong {
    color: var(--text);
  }
  .kpi-card-visual {
    position: absolute;
    right: 0; bottom: 0;
    pointer-events: none;
    z-index: 1;
    opacity: 0.35;
  }
  .kpi-card-radial {
    position: absolute;
    right: 1.2rem;
    bottom: 1.2rem;
    width: 36px;
    height: 36px;
  }
  .circular-chart {
    display: block;
    max-width: 100%;
    max-height: 100%;
  }
  .circle-bg {
    fill: none;
    stroke: rgba(255, 255, 255, 0.05);
    stroke-width: 3.8;
  }
  .circle {
    fill: none;
    stroke-width: 3.8;
    stroke-linecap: round;
    stroke: var(--accent2);
    transition: stroke-dasharray 0.3s ease;
  }

  /* SPLIT GRID WORKSPACE */
  .dashboard-grid {
    display: grid;
    grid-template-columns: 1.15fr 0.85fr;
    gap: 1.8rem;
  }
  .dashboard-col {
    display: flex;
    flex-direction: column;
    gap: 1.8rem;
  }
  :global(.panel-card) {
    background: transparent !important;
    border: none !important;
    border-radius: 0 !important;
    padding: 0 !important;
    box-shadow: none !important;
  }
  .panel-header {
    margin-bottom: 1.5rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    padding-bottom: 1rem;
  }
  .panel-header h3, .panel-header-row h3 {
    font-family: 'DM Serif Display', serif;
    font-size: 1.35rem;
    color: var(--text);
    font-weight: 400;
  }
  .panel-subtitle {
    font-size: 0.78rem;
    color: var(--muted);
    margin-top: 0.25rem;
  }
  .panel-header-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 1.5rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    padding-bottom: 1rem;
  }

  /* Message dispatcher templates chip list */
  .templates-section {
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    margin-bottom: 1.2rem;
  }
  .templates-label {
    font-size: 0.65rem;
    color: var(--muted);
    letter-spacing: 0.05em;
  }
  .templates-list {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }
  .template-chip {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid var(--border);
    color: var(--text);
    border-radius: 6px;
    font-size: 0.72rem;
    padding: 0.35rem 0.7rem;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .template-chip:hover {
    border-color: var(--accent);
    color: var(--accent);
    background: rgba(200, 169, 110, 0.05);
  }

  .grid-form-fields {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.2rem;
    margin-bottom: 1.2rem;
  }
  .cyber-input-group textarea {
    width: 100%;
    height: 110px;
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 0.85rem;
    color: var(--text);
    font-size: 0.88rem;
    resize: none;
    outline: none;
    transition: border-color 0.2s;
  }
  .cyber-input-group textarea:focus {
    border-color: var(--accent);
  }
  .dispatch-btn {
    width: 100%;
    margin-top: 0.5rem;
  }

  /* BAR CHART COMPONENT */
  .bar-chart-container {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 0.2rem 0;
  }
  .bar-chart-row {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }
  .bar-chart-label {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.78rem;
  }
  .dept-name { color: var(--text); }
  .dept-count { color: var(--accent); font-size: 0.72rem; }
  .bar-chart-track {
    width: 100%;
    height: 6px;
    background: rgba(255, 255, 255, 0.03);
    border-radius: 10px;
    overflow: hidden;
  }
  .bar-chart-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--accent2) 0%, var(--accent) 100%);
    border-radius: 10px;
    transition: width 0.8s cubic-bezier(0.1, 0.8, 0.2, 1);
  }

  /* TABLE CSS STYLES */
  .table-compact-container {
    overflow-x: auto;
  }
  .dashboard-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.82rem;
    text-align: left;
  }
  .dashboard-table th {
    font-family: 'DM Mono', monospace;
    font-size: 0.68rem;
    color: var(--muted);
    padding: 0.75rem 0.6rem;
    border-bottom: 1px solid var(--border);
    letter-spacing: 0.05em;
    text-transform: uppercase;
    white-space: nowrap;
  }
  .dashboard-table td {
    padding: 0.8rem 0.6rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.02);
    color: var(--text);
    white-space: nowrap;
  }
  .dashboard-table tbody tr:hover td {
    background: rgba(255, 255, 255, 0.012);
  }
  .table-cell-title {
    max-width: 150px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .overdue-date {
    color: var(--danger);
    font-weight: 500;
  }
  .action-btn-small {
    background: rgba(200, 169, 110, 0.12);
    border: 1px solid rgba(200, 169, 110, 0.2);
    color: var(--accent);
    font-family: 'DM Mono', monospace;
    font-size: 0.65rem;
    font-weight: 600;
    padding: 0.25rem 0.6rem;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;
  }
  .action-btn-small:hover {
    background: var(--accent);
    color: #1a1409;
    box-shadow: 0 2px 8px rgba(200,169,110,0.3);
  }
  .table-state-placeholder {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 2.5rem 1rem;
    text-align: center;
    color: var(--muted);
    gap: 0.6rem;
    font-size: 0.8rem;
  }
  .success-icon-badge {
    background: rgba(78, 173, 133, 0.12);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.2);
    border-radius: 50%;
    width: 28px; height: 28px;
    display: flex; align-items: center; justify-content: center;
    font-size: 0.9rem;
    font-weight: bold;
  }
  .table-refresh-link {
    background: none;
    border: none;
    color: var(--accent);
    font-size: 0.65rem;
    cursor: pointer;
    letter-spacing: 0.05em;
    opacity: 0.7;
    transition: opacity 0.2s;
  }
  .table-refresh-link:hover { opacity: 1; }
  .view-more-records-btn {
    width: 100%;
    background: none;
    border: 1px dashed var(--border);
    color: var(--muted);
    font-size: 0.7rem;
    padding: 0.6rem;
    margin-top: 0.8rem;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .view-more-records-btn:hover {
    color: var(--accent);
    border-color: var(--accent);
    background: rgba(255,255,255,0.01);
  }

  /* BORROWERS DIRECTORY TAB STYLE */
  .explorer-container {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  .filter-card {
    padding: 1.2rem 1.8rem !important;
  }
  .filter-controls-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 1.2rem;
    align-items: flex-end;
  }
  .filter-controls-grid select, .filter-controls-grid input {
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 0.8rem;
    color: var(--text);
    font-size: 0.88rem;
    width: 100%;
    outline: none;
    transition: all 0.2s;
  }
  .filter-controls-grid select:focus, .filter-controls-grid input:focus {
    border-color: var(--accent);
  }
  .checkbox-container {
    display: flex;
    align-items: center;
    height: 42px;
  }
  .glow-checkbox {
    display: inline-flex;
    align-items: center;
    gap: 0.6rem;
    cursor: pointer;
    user-select: none;
  }
  .glow-checkbox input { display: none; }
  .checkbox-visual {
    width: 18px; height: 18px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: rgba(0,0,0,0.3);
    position: relative;
    transition: all 0.2s ease;
  }
  .glow-checkbox input:checked + .checkbox-visual {
    background: var(--accent2);
    border-color: var(--accent2);
    box-shadow: 0 0 10px rgba(124, 111, 205, 0.4);
  }
  .glow-checkbox input:checked + .checkbox-visual::after {
    content: '✓';
    position: absolute;
    color: #fff;
    font-size: 0.72rem;
    font-weight: bold;
    left: 50%; top: 50%;
    transform: translate(-50%, -50%);
  }
  .checkbox-label {
    font-size: 0.8rem;
    color: var(--muted);
  }
  .glow-checkbox:hover .checkbox-label {
    color: var(--text);
  }
  .apply-filter-btn {
    height: 42px;
    display: flex; align-items: center; justify-content: center;
  }
  
  .table-panel-card {
    padding: 0 !important;
  }
  .table-container {
    overflow-x: auto;
  }
  .full-table th.sortable-header {
    cursor: pointer;
    transition: color 0.2s;
  }
  .full-table th.sortable-header:hover {
    color: var(--accent);
  }
  .row-overdue-alert td {
    background: rgba(224, 108, 108, 0.015);
  }
  .row-overdue-alert:hover td {
    background: rgba(224, 108, 108, 0.035) !important;
  }
  .status-badge {
    display: inline-flex;
    padding: 0.25rem 0.6rem;
    border-radius: 20px;
    font-family: 'DM Mono', monospace;
    font-size: 0.65rem;
    font-weight: 600;
  }
  .status-badge-danger {
    background: rgba(224, 108, 108, 0.1);
    color: var(--danger);
    border: 1px solid rgba(224, 108, 108, 0.2);
  }
  .status-badge-success {
    background: rgba(78, 173, 133, 0.1);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.2);
  }
  .row-actions {
    display: flex;
    gap: 0.45rem;
    align-items: center;
  }
  .row-btn {
    border: none;
    font-size: 0.7rem;
    font-weight: 600;
    padding: 0.35rem 0.7rem;
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .btn-notify {
    background: rgba(200, 169, 110, 0.12);
    color: var(--accent);
    border: 1px solid rgba(200, 169, 110, 0.2);
  }
  .btn-notify:hover {
    background: var(--accent);
    color: #1a1409;
    box-shadow: 0 2px 10px rgba(200,169,110,0.3);
  }
  .btn-return {
    background: rgba(78, 173, 133, 0.12);
    color: var(--success);
    border: 1px solid rgba(78, 173, 133, 0.25);
  }
  .btn-return:hover {
    background: var(--success);
    color: #fff;
    box-shadow: 0 2px 10px rgba(78,173,133,0.3);
  }
  .no-contact-label {
    font-size: 0.68rem;
    color: var(--muted);
    font-style: italic;
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border);
    padding: 0.2rem 0.45rem;
    border-radius: 4px;
  }
  .table-cell-title-long {
    max-width: 320px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pagination-controls {
    display: flex;
    align-items: center;
    gap: 0.8rem;
  }
  .page-btn {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border);
    color: var(--accent);
    border-radius: 6px;
    padding: 0.35rem 0.75rem;
    font-size: 0.72rem;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .page-btn:hover:not(:disabled) {
    border-color: var(--accent);
    background: rgba(255,255,255,0.05);
  }
  .page-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }
  .page-indicator {
    font-size: 0.72rem;
    color: var(--muted);
  }

  /* GATEWAY HUD STYLE */
  .gateway-hub {
    width: 100%;
  }
  .gateway-status-checking {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 5rem 2rem;
  }
  .gateway-status-checking h3 {
    font-family: 'DM Serif Display', serif;
    font-size: 1.5rem;
    margin-top: 1.5rem;
  }
  .gateway-status-checking p {
    font-size: 0.85rem;
    margin-top: 0.4rem;
  }
  .spinner-circle {
    width: 32px; height: 32px;
    border: 2px solid rgba(200, 169, 110, 0.15);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: rotateSpinner 0.8s linear infinite;
  }
  @keyframes rotateSpinner {
    to { transform: rotate(360deg); }
  }

  .gateway-grid-layout {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.8rem;
  }
  .cyber-divider {
    display: flex;
    align-items: center;
    text-align: center;
    color: var(--muted);
    font-size: 0.62rem;
    letter-spacing: 0.08em;
    margin: 1.5rem 0;
  }
  .cyber-divider::before, .cyber-divider::after {
    content: '';
    flex: 1;
    border-bottom: 1px solid var(--border);
  }
  .cyber-divider:not(:empty)::before { margin-right: 0.8rem; }
  .cyber-divider:not(:empty)::after { margin-left: 0.8rem; }

  .inline-input-action {
    display: flex;
    gap: 0.5rem;
    width: 100%;
  }
  .inline-input-action input {
    flex: 1;
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 0.8rem;
    color: var(--text);
  }
  .inline-action-btn {
    margin-top: 0;
    width: auto;
    padding: 0 1.2rem;
    font-size: 0.85rem;
  }

  .instance-controls-console {
    margin-top: 1.8rem;
    padding-top: 1.5rem;
    border-top: 1px dashed var(--border);
  }
  .section-tag-sub {
    font-size: 0.65rem;
    color: var(--muted);
    display: block;
    margin-bottom: 0.8rem;
    letter-spacing: 0.05em;
  }
  .instance-control-buttons {
    display: grid;
    grid-template-columns: 1fr;
    gap: 0.65rem;
  }
  .cyber-console-btn {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 0.65rem;
    border-radius: 8px;
    cursor: pointer;
    font-family: 'DM Mono', monospace;
    font-size: 0.75rem;
    transition: all 0.2s;
  }
  .cyber-console-btn:hover {
    border-color: var(--accent);
    color: var(--accent);
    background: rgba(255,255,255,0.04);
  }
  .btn-danger-console {
    color: var(--danger);
  }
  .btn-danger-console:hover {
    border-color: var(--danger);
    color: var(--danger);
    background: rgba(224, 108, 108, 0.05);
  }

  /* Authn frame styles */
  .auth-sections {
    display: grid;
    grid-template-columns: 1fr;
    gap: 2.2rem;
  }
  .auth-method h4 {
    font-size: 0.72rem;
    color: var(--accent);
    letter-spacing: 0.08em;
    margin-bottom: 1.2rem;
  }
  .qr-code-frame {
    position: relative;
    background: #fff;
    padding: 0.85rem;
    border-radius: 14px;
    width: 250px; height: 250px;
    margin: 0 auto;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border: 1px solid rgba(255,255,255,0.1);
  }
  .qr-code-frame img {
    width: 100%; height: 100%;
    object-fit: contain;
  }
  @keyframes qrScan {
    0% { top: 0%; opacity: 0.8; }
    50% { top: 100%; opacity: 0.8; }
    100% { top: 0%; opacity: 0.8; }
  }
  .qr-scan-line {
    position: absolute;
    left: 0;
    width: 100%;
    height: 3px;
    background: linear-gradient(90deg, transparent, var(--accent), transparent);
    box-shadow: 0 0 10px var(--accent), 0 0 20px var(--accent);
    animation: qrScan 3s linear infinite;
    pointer-events: none;
    z-index: 5;
  }
  .qr-loading-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: #1a1409;
    font-size: 0.75rem;
    gap: 0.65rem;
    text-align: center;
    padding: 1.5rem;
  }
  .frame-instruction {
    font-size: 0.65rem;
    color: var(--muted);
    text-align: center;
    margin-top: 1rem;
    letter-spacing: 0.03em;
  }
  .pairing-auth-method {
    border-top: 1px dashed var(--border);
    padding-top: 1.8rem;
  }
  .pair-btn-dispatch {
    width: 100%;
  }
  .pairing-code-terminal {
    margin-top: 1.5rem;
    background: rgba(200, 169, 110, 0.05);
    border: 2px dashed rgba(200, 169, 110, 0.25);
    border-radius: 10px;
    padding: 1.1rem;
    text-align: center;
  }
  .terminal-label {
    font-size: 0.62rem;
    color: var(--muted);
    display: block;
    letter-spacing: 0.08em;
  }
  .terminal-code {
    font-size: 1.85rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 5px;
    margin-top: 0.4rem;
  }

  .gateway-unselected-placeholder {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 5rem 2rem;
    color: var(--muted);
    gap: 0.75rem;
  }
  .unselected-icon-glow {
    font-size: 2.2rem;
    opacity: 0.75;
  }
  .gateway-unselected-placeholder h4 {
    font-family: 'DM Serif Display', serif;
    font-size: 1.25rem;
    color: var(--text);
  }
  .gateway-unselected-placeholder p {
    font-size: 0.82rem;
    max-width: 280px;
    line-height: 1.5;
  }

  /* SYSTEM LOGS TABLE SCREEN CSS */
  .log-clear-btn {
    background: none;
    border: none;
    color: var(--danger);
    font-size: 0.65rem;
    cursor: pointer;
    letter-spacing: 0.05em;
    transition: opacity 0.2s;
  }
  .log-clear-btn:hover { opacity: 0.8; }
  .console-log-body {
    padding: 0 !important;
  }
  .log-console {
    background: rgba(0, 0, 0, 0.45);
    padding: 1.2rem;
    height: 480px;
    overflow-y: auto;
    border-radius: 0 0 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    font-size: 0.78rem;
    line-height: 1.5;
    box-shadow: inset 0 8px 20px rgba(0,0,0,0.5);
  }
  .log-line {
    word-break: break-all;
    display: flex;
    gap: 0.6rem;
  }
  .log-timestamp {
    color: var(--muted);
    flex-shrink: 0;
  }
  .log-type-tag {
    flex-shrink: 0;
    font-weight: 600;
  }
  .log-info { color: #8cb4ff; }
  .log-info .log-type-tag { color: #3b82f6; }
  .log-success { color: #a3f7bf; }
  .log-success .log-type-tag { color: var(--success); }
  .log-warning { color: #ffe699; }
  .log-warning .log-type-tag { color: var(--accent); }
  .log-error { color: #ffadad; }
  .log-error .log-type-tag { color: var(--danger); }

  /* spinner styling */
  .spinner-small {
    width: 20px; height: 20px;
    border: 2px solid rgba(255,255,255,0.05);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: rotateSpinner 0.8s linear infinite;
  }

  /* --- UTILITY & ANIMATION CLASSES --- */
  .font-mono { font-family: 'DM Mono', monospace; }
  .font-semibold { font-weight: 600; }
  .animate-fade {
    animation: fadeIn 0.35s cubic-bezier(0.16, 1, 0.3, 1);
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(6px); }
    to { opacity: 1; transform: translateY(0); }
  }

  /* --- RESPONSIVE STYLE RULES --- */
  @media (max-width: 1024px) {
    .dashboard-container {
      grid-template-columns: 1fr;
    }
    .dashboard-sidebar {
      border-right: none;
      border-bottom: 1px solid var(--border);
      flex-direction: row;
      flex-wrap: wrap;
      align-items: center;
      gap: 1.5rem;
      padding: 1.5rem;
    }
    .sidebar-brand {
      border-bottom: none;
      margin-bottom: 0;
      padding-bottom: 0;
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
      width: 100%;
    }
    .sidebar-nav {
      flex-direction: row;
      flex-wrap: wrap;
      width: 100%;
      gap: 0.5rem;
    }
    .nav-item {
      width: auto;
      padding: 0.6rem 1rem;
    }
    .nav-item.active::before {
      left: 20%; right: 20%; top: auto; bottom: 0;
      width: auto; height: 2px;
    }
    .sidebar-footer {
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      border-top: none;
      padding-top: 0.5rem;
    }
    .kpi-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }

  @media (max-width: 900px) {
    .dashboard-grid {
      grid-template-columns: 1fr;
    }
    .filter-controls {
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
    }
    .checkbox-container {
      height: auto;
    }
    .apply-filter-btn {
      grid-column: span 2;
    }
    .gateway-grid-layout {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 600px) {
    .kpi-grid {
      grid-template-columns: 1fr;
    }
    .filter-controls {
      grid-template-columns: 1fr;
    }
    .apply-filter-btn {
      grid-column: span 1;
    }
    .grid-form-fields {
      grid-template-columns: 1fr;
    }
    .workspace-header {
      flex-direction: column;
      align-items: flex-start;
      gap: 0.8rem;
    }
  }

  /* --- MASTER SEARCH STYLINGS --- */
  .master-search-container {
    display: flex;
    flex-direction: column;
    gap: 1.8rem;
    width: 100%;
  }
  :global(.search-inputs-card) {
    padding: 0 !important;
    margin-bottom: 1.5rem !important;
  }
  .search-inputs-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.2rem;
    margin-bottom: 1.5rem;
  }
  .search-inputs-grid input {
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.8rem;
    color: var(--text);
    font-size: 0.88rem;
    outline: none;
    transition: all 0.2s;
  }
  .search-inputs-grid input:focus {
    border-color: var(--accent);
    background: rgba(0, 0, 0, 0.45);
  }
  .search-actions-row {
    display: flex;
    justify-content: flex-end;
    gap: 1rem;
    border-top: 1px dashed var(--border);
    padding-top: 1.2rem;
  }
  .clear-search-btn {
    width: auto !important;
    padding: 0.6rem 1.4rem !important;
  }
  .execute-search-btn {
    width: auto !important;
    padding: 0.6rem 1.8rem !important;
    margin-top: 0 !important;
  }
  .search-split-layout {
    display: grid;
    grid-template-columns: 1fr 1.25fr;
    gap: 1.8rem;
    align-items: start;
  }
  .results-list-body {
    padding: 0 !important;
  }
  .results-scrollable {
    max-height: 480px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
  }
  .results-scrollable::-webkit-scrollbar {
    width: 4px;
  }
  .results-scrollable::-webkit-scrollbar-thumb {
    background: var(--border);
    border-radius: 4px;
  }
  .member-result-item {
    display: flex;
    align-items: center;
    gap: 0.8rem;
    padding: 0.9rem 1.2rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.02);
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .member-result-item:hover {
    background: rgba(255, 255, 255, 0.015);
  }
  .member-result-item.selected {
    background: rgba(200, 169, 110, 0.05);
    border-left: 3px solid var(--accent);
  }
  .member-result-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.06);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    color: var(--accent);
    font-size: 0.85rem;
  }
  .member-result-info {
    display: flex;
    flex-direction: column;
    flex-grow: 1;
  }
  .member-res-name {
    font-size: 0.85rem;
    color: var(--text);
  }
  .member-res-sub {
    font-size: 0.7rem;
    color: var(--muted);
    margin-top: 0.2rem;
  }
  .member-res-class-tag {
    font-size: 0.62rem;
    color: var(--muted);
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border);
    padding: 0.15rem 0.45rem;
    border-radius: 4px;
  }
  .profile-details-body {
    padding: 0.2rem 0;
  }
  .profile-header-meta {
    display: flex;
    align-items: center;
    gap: 1.2rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    padding-bottom: 1.4rem;
    margin-bottom: 1.4rem;
  }
  .profile-avatar-large {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--accent) 0%, #a2834b 100%);
    color: #1a1409;
    font-weight: 700;
    font-size: 1.2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .profile-title-block h4 {
    font-family: 'DM Serif Display', serif;
    font-size: 1.2rem;
    color: var(--text);
    font-weight: 400;
  }
  .profile-status-badge {
    font-size: 0.58rem;
    padding: 0.15rem 0.5rem;
    border-radius: 4px;
    display: inline-block;
    margin-top: 0.3rem;
  }
  .profile-info-grid {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    font-size: 0.76rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    padding-bottom: 1.5rem;
    margin-bottom: 1.5rem;
  }
  .profile-info-row {
    display: flex;
    justify-content: space-between;
    padding-bottom: 0.25rem;
  }
  .borrows-ledger-section h5 {
    font-size: 0.72rem;
    color: var(--accent);
    letter-spacing: 0.06em;
    margin-bottom: 0.8rem;
  }
  .ledger-empty {
    font-size: 0.72rem;
    color: var(--muted);
    background: rgba(0, 0, 0, 0.15);
    padding: 0.8rem;
    border-radius: 8px;
    text-align: center;
    border: 1px dashed var(--border);
  }
  .ledger-list {
    display: flex;
    flex-direction: column;
    gap: 0.6rem;
  }
  .ledger-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: rgba(255, 255, 255, 0.01);
    border: 1px solid var(--border);
    padding: 0.7rem 0.9rem;
    border-radius: 8px;
  }
  .overdue-ledger-item {
    border-color: rgba(224, 108, 108, 0.25);
    background: rgba(224, 108, 108, 0.01);
  }
  .ledger-book-details {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
  }
  .ledger-title {
    font-size: 0.78rem;
    color: var(--text);
  }
  .ledger-author {
    font-size: 0.65rem;
    color: var(--muted);
  }
  .ledger-date-info {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 0.15rem;
  }
  .ledger-due {
    font-size: 0.68rem;
  }
  .ledger-overdue-tag {
    font-size: 0.6rem;
    color: var(--danger);
    font-weight: 600;
  }
  .profile-unselected-state {
    font-size: 0.75rem;
    color: var(--muted);
    text-align: center;
    padding: 4rem 1.5rem;
    border: 1px dashed var(--border);
    border-radius: 12px;
    background: rgba(0,0,0,0.1);
  }
  .search-icon-placeholder {
    font-size: 2rem;
    opacity: 0.5;
  }

  @media (max-width: 900px) {
    .search-inputs-grid {
      grid-template-columns: 1fr 1fr;
    }
    .search-split-layout {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 600px) {
    .search-inputs-grid {
      grid-template-columns: 1fr;
    }
  }

  /* --- REPORTS TAB & PRINT STYLES --- */
  .cyber-select {
    background: rgba(0, 0, 0, 0.25);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.65rem 0.8rem;
    color: var(--text);
    font-size: 0.85rem;
    outline: none;
    cursor: pointer;
    transition: all 0.2s;
  }
  .cyber-select:focus {
    border-color: var(--accent);
  }
  .cyber-select option {
    background: var(--surface);
    color: var(--text);
  }
  .class-chips-container {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 0.35rem;
  }
  .class-chip {
    background: rgba(0, 0, 0, 0.25);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 0.55rem 0.85rem;
    color: var(--text);
    font-size: 0.78rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
    user-select: none;
    text-transform: uppercase;
  }
  .class-chip:hover {
    border-color: rgba(255, 255, 255, 0.4);
    background: rgba(255, 255, 255, 0.05);
  }
  .class-chip.selected {
    background: rgba(212, 175, 55, 0.15); /* matching gold/amber style */
    border-color: var(--accent);
    color: var(--accent);
    box-shadow: 0 0 8px rgba(212, 175, 55, 0.2);
  }
  .cyber-text-input {
    background: rgba(0, 0, 0, 0.25);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.65rem 0.8rem;
    color: var(--text);
    font-size: 0.85rem;
    outline: none;
    transition: all 0.2s;
  }
  .cyber-text-input:focus {
    border-color: var(--accent);
  }
  .radio-label {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.8rem;
    color: var(--text);
    cursor: pointer;
  }
  .radio-label input {
    cursor: pointer;
    accent-color: var(--accent);
  }
  .report-preview-outer-wrap {
    margin-top: 2rem;
    width: 100%;
  }
  .report-preview-paper-card {
    background: #ffffff !important;
    color: #1a1a1f !important;
    border: 1px solid #e0e0e0;
    border-radius: 12px;
    padding: 3rem;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.15);
    width: 100%;
  }
  .report-preview-paper-card h2, 
  .report-preview-paper-card h3, 
  .report-preview-paper-card h4, 
  .report-preview-paper-card th, 
  .report-preview-paper-card td,
  .report-preview-paper-card span,
  .report-preview-paper-card div {
    color: #1a1a1f !important;
  }
  .report-college-title {
    font-size: 1.55rem;
    font-weight: bold;
    margin-bottom: 0.2rem;
  }
  .report-college-location {
    font-size: 0.95rem;
    font-weight: 500;
    margin-bottom: 1rem;
    letter-spacing: 0.02em;
  }
  .report-title-line {
    border-top: 1px solid #1a1a1f;
    border-bottom: 1px solid #1a1a1f;
    padding: 0.4rem 0;
    margin: 0.5rem 0;
  }
  .report-title-text {
    font-size: 1.15rem;
    letter-spacing: 0.08em;
  }
  .report-meta-row {
    font-size: 0.8rem;
    margin-bottom: 1.8rem;
    display: flex;
    justify-content: space-between;
  }
  .report-member-group {
    margin-bottom: 2.2rem;
    page-break-inside: avoid;
  }
  .report-member-header {
    font-size: 0.9rem;
    border-bottom: 1px dashed #cccccc;
    padding-bottom: 0.35rem;
    margin-bottom: 0.75rem;
  }
  .report-data-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 0.8rem;
    font-size: 0.82rem;
  }
  .table-header-underline {
    border-bottom: 1px solid #1a1a1f;
  }
  .report-data-table th {
    padding: 0.4rem 0.2rem;
    font-weight: bold;
  }
  .report-data-table td {
    padding: 0.35rem 0.2rem;
    vertical-align: top;
  }
  .book-data-row {
    border-bottom: 1px solid #f0f0f0;
  }
  .report-data-table th[align="right"], .report-data-table td[align="right"] {
    text-align: right;
  }
  .report-member-footer {
    font-size: 0.82rem;
    margin-top: 0.4rem;
    padding-right: 0.2rem;
  }
  .book-subtotal {
    margin-bottom: 0.2rem;
  }
  .paid-by-line {
    margin-bottom: 0.5rem;
  }
  .subtotal-val {
    display: inline-block;
    width: 110px;
    text-align: right;
  }
  .report-grand-footer {
    border-top: 1px solid #1a1a1f;
    padding-top: 0.8rem;
    font-size: 0.92rem;
    margin-top: 2rem;
  }
  .grand-total-label {
    margin-right: 1.5rem;
  }
  .grand-total-val {
    display: inline-block;
    width: 110px;
    text-align: right;
  }
  .border-double-bottom {
    border-bottom: 3px double #1a1a1f;
    padding-bottom: 0.15rem;
  }
  .report-empty-state {
    font-size: 0.9rem;
    padding: 4rem 0;
    color: #666 !important;
  }
  
  .print-only-block {
    display: none;
  }
  
  @media print {
    :global(body), :global(html) {
      background: #ffffff !important;
      color: #000000 !important;
    }
    :global(header), :global(footer), :global(.beta-banner), :global(main) {
      padding: 0 !important;
      margin: 0 !important;
    }
    :global(header), :global(footer), :global(.beta-banner), .no-print {
      display: none !important;
    }
    .dashboard-sidebar, .workspace-header {
      display: none !important;
    }
    .dashboard-container {
      display: block !important;
      grid-template-columns: none !important;
      height: auto !important;
      min-height: 0 !important;
    }
    .dashboard-workspace {
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
    }
    .report-preview-outer-wrap {
      margin-top: 0 !important;
    }
    .report-preview-paper-card {
      border: none !important;
      box-shadow: none !important;
      padding: 0 !important;
      background: transparent !important;
    }
    .print-only-block {
      display: block !important;
    }
  }
</style>
