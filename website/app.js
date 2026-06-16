// Klassivo Web App Simulator and Landing Page Interactivity

document.addEventListener('DOMContentLoaded', () => {
  // --- DOM Elements ---
  const roleButtons = document.querySelectorAll('.role-btn');
  const simScreens = document.querySelectorAll('.sim-screen');
  const menuToggle = document.getElementById('menu-toggle');
  const navList = document.querySelector('.nav-list');
  const contactForm = document.getElementById('klassivo-contact-form');
  
  // --- Simulator Interactive Elements ---
  const simEmail = document.getElementById('sim-email');
  const simRolePicker = document.getElementById('sim-role-picker');
  const btnSubmitAttendance = document.getElementById('btn-submit-attendance');
  const attendanceStatus = document.getElementById('attendance-status');
  const btnApproveLeave = document.getElementById('btn-approve-leave');
  const btnDenyLeave = document.getElementById('btn-deny-leave');
  const leaveRequestPanel = document.getElementById('leave-request-panel');
  const leaveSuccessPanel = document.getElementById('leave-success-panel');
  const pendingLeaveCount = document.getElementById('pending-leave-count');

  // --- 1. Simulator Role Tab Switching ---
  function switchScreen(roleId) {
    let targetScreenId = 'screen-role-selection';
    
    // Map the selected option to its respective screen ID
    if (roleId === 'selection') targetScreenId = 'screen-role-selection';
    else if (roleId === 'staff-login') targetScreenId = 'screen-staff-login';
    else if (roleId === 'admin-login') targetScreenId = 'screen-admin-login';
    else if (roleId === 'admin-dashboard') targetScreenId = 'screen-admin-dashboard';
    else if (roleId === 'teacher') targetScreenId = 'screen-teacher';
    else if (roleId === 'coordinator') targetScreenId = 'screen-coordinator';
    else if (roleId === 'principal') targetScreenId = 'screen-principal';
    else if (roleId === 'owner') targetScreenId = 'screen-owner';
    else if (roleId === 'guardian') targetScreenId = 'screen-guardian';

    // Update screen active states
    simScreens.forEach(screen => {
      if (screen.id === targetScreenId) {
        screen.classList.add('active');
      } else {
        screen.classList.remove('active');
      }
    });

    // Update outer button active highlights
    roleButtons.forEach(btn => {
      let isTarget = false;
      if (roleId === 'selection' && btn.id === 'btn-role-selection') isTarget = true;
      else if (roleId === 'staff-login' && btn.id === 'btn-staff-login') isTarget = true;
      else if (['teacher', 'coordinator', 'principal', 'owner', 'guardian', 'admin-dashboard'].includes(roleId) && btn.id === 'btn-dashboards') isTarget = true;

      if (isTarget) {
        btn.classList.add('active');
        btn.setAttribute('aria-selected', 'true');
      } else {
        btn.classList.remove('active');
        btn.setAttribute('aria-selected', 'false');
      }
    });
  }

  // Bind clicks to outer buttons
  roleButtons.forEach(button => {
    button.addEventListener('click', () => {
      if (button.id === 'btn-role-selection') {
        switchScreen('selection');
      } else if (button.id === 'btn-staff-login') {
        switchScreen('staff-login');
      } else if (button.id === 'btn-dashboards') {
        // Default to teacher dashboard on general dashboard control tab click
        switchScreen('teacher');
      }
    });
  });

  // Global functions exposed for inner simulator clicks
  window.selectRoleSim = (roleId) => {
    switchScreen(roleId);
  };

  window.resetSim = () => {
    switchScreen('selection');
    resetAttendanceSim();
    resetLeaveSim();
  };

  // Update email credentials in simulator based on role selection
  window.updateSimCredentials = () => {
    if (!simRolePicker || !simEmail) return;
    const role = simRolePicker.value;
    if (role === 'teacher') {
      simEmail.value = 'meera.sen@klassivo.com';
    } else if (role === 'coordinator') {
      simEmail.value = 'rajesh.sharma@klassivo.com';
    } else if (role === 'principal') {
      simEmail.value = 'devendra.roy@klassivo.com';
    } else if (role === 'owner') {
      simEmail.value = 'suresh.patel@klassivo.com';
    }
  };

  // Sign-in staff click simulation
  window.authenticateStaffSim = () => {
    if (!simRolePicker) return;
    const role = simRolePicker.value;
    switchScreen(role);
  };

  // Sign-in admin click simulation
  window.authenticateAdminSim = () => {
    switchScreen('admin-dashboard');
  };

  // --- 2. Interactive Simulator Features ---

  // A. Teacher: Mark Attendance Action
  if (btnSubmitAttendance) {
    btnSubmitAttendance.addEventListener('click', () => {
      // Transition status chip to saved
      attendanceStatus.textContent = 'Saved';
      attendanceStatus.classList.add('saved');
      
      // Calculate active checklist values
      const total = document.querySelectorAll('.student-chk').length;
      const present = document.querySelectorAll('.student-chk:checked').length;
      
      btnSubmitAttendance.textContent = 'Submitted Successfully!';
      btnSubmitAttendance.disabled = true;
      btnSubmitAttendance.style.backgroundColor = 'var(--success)';
      btnSubmitAttendance.style.color = 'var(--white)';

      setTimeout(() => {
        alert(`Attendance submitted!\nPresent: ${present}/${total}\nAbsent: ${total - present}`);
      }, 100);
    });
  }

  function resetAttendanceSim() {
    if (btnSubmitAttendance) {
      btnSubmitAttendance.textContent = 'Submit Attendance';
      btnSubmitAttendance.disabled = false;
      btnSubmitAttendance.style.backgroundColor = '';
      btnSubmitAttendance.style.color = '';
      attendanceStatus.textContent = 'Unsaved';
      attendanceStatus.classList.remove('saved');
    }
  }

  // B. Coordinator: Approve Leave Action
  if (btnApproveLeave) {
    btnApproveLeave.addEventListener('click', () => {
      leaveRequestPanel.classList.add('hidden');
      leaveSuccessPanel.classList.remove('hidden');
      pendingLeaveCount.textContent = '0';
    });
  }

  if (btnDenyLeave) {
    btnDenyLeave.addEventListener('click', () => {
      leaveRequestPanel.classList.add('hidden');
      alert('Leave Request Denied.');
      pendingLeaveCount.textContent = '0';
    });
  }

  function resetLeaveSim() {
    if (leaveRequestPanel && leaveSuccessPanel && pendingLeaveCount) {
      leaveRequestPanel.classList.remove('hidden');
      leaveSuccessPanel.classList.add('hidden');
      pendingLeaveCount.textContent = '1';
    }
  }

  // --- 3. Responsive Navigation ---
  if (menuToggle) {
    menuToggle.addEventListener('click', () => {
      const isVisible = navList.style.display === 'flex';
      navList.style.display = isVisible ? 'none' : 'flex';
      
      // Toggle menu icon
      const icon = menuToggle.querySelector('i');
      if (icon) {
        icon.className = isVisible ? 'fa-solid fa-bars' : 'fa-solid fa-xmark';
      }
    });
  }

  // Close nav on list item click for mobile
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach(item => {
    item.addEventListener('click', () => {
      if (window.innerWidth <= 768) {
        navList.style.display = 'none';
        const icon = menuToggle.querySelector('i');
        if (icon) icon.className = 'fa-solid fa-bars';
      }
    });
  });

  // --- 4. Inquiry Form Submission ---
  if (contactForm) {
    contactForm.addEventListener('submit', (e) => {
      e.preventDefault();
      
      const name = document.getElementById('input-name').value;
      const school = document.getElementById('input-school').value;
      
      // Visual feedback
      const submitBtn = document.getElementById('btn-submit-form');
      submitBtn.textContent = 'Inquiry Sent!';
      submitBtn.disabled = true;
      submitBtn.style.backgroundColor = 'var(--success)';
      
      setTimeout(() => {
        alert(`Thank you, ${name}!\nYour inquiry for ${school} has been simulated successfully. We will not transmit any data as this is a local preview.`);
        
        // Reset form
        contactForm.reset();
        submitBtn.textContent = 'Send Inquiry';
        submitBtn.disabled = false;
        submitBtn.style.backgroundColor = '';
      }, 500);
    });
  }
});
