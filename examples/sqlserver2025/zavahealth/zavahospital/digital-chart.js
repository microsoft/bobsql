// Digital Patient Chart Application
// Mock data based on ZavaHealth Hospital schema

console.log('Digital Patient Chart script loaded');

class PatientChartApp {
    constructor() {
        console.log('PatientChartApp constructor called');
        this.currentPatient = null;
        this.refreshInterval = null;
        this.vitalsInterval = null;
        this.init();
    }

    init() {
        console.log('Initializing app...');
        try {
            this.setupEventListeners();
            this.loadMockData();
            this.startAutoRefresh();
        } catch (error) {
            console.error('Error during initialization:', error);
            this.hideLoading();
            this.showToast('Failed to initialize app: ' + error.message, true);
        }
    }

    setupEventListeners() {
        const refreshBtn = document.getElementById('refreshBtn');
        refreshBtn.addEventListener('click', () => {
            this.loadMockData();
            this.showToast('Data refreshed', false);
        });

        // AI Health Assistance button
        const aiAssistBtn = document.getElementById('aiAssistBtn');
        aiAssistBtn.addEventListener('click', () => {
            this.showAiModal();
        });

        // Close AI modal
        const closeAiModal = document.getElementById('closeAiModal');
        closeAiModal.addEventListener('click', () => {
            this.hideAiModal();
        });

        const dismissAiBtn = document.getElementById('dismissAiBtn');
        dismissAiBtn.addEventListener('click', () => {
            this.hideAiModal();
        });

        // Order X-ray button
        const orderXrayBtn = document.getElementById('orderXrayBtn');
        orderXrayBtn.addEventListener('click', () => {
            this.orderXray();
        });

        // Close modal when clicking outside
        const aiModal = document.getElementById('aiModal');
        aiModal.addEventListener('click', (e) => {
            if (e.target === aiModal) {
                this.hideAiModal();
            }
        });
    }

    startAutoRefresh() {
        // Auto-refresh every 30 seconds
        this.refreshInterval = setInterval(() => {
            this.loadMockData(true);
        }, 30000);
    }

    startVitalSignsSimulation() {
        // Update vital signs every 3-5 seconds to simulate real monitoring
        this.vitalsInterval = setInterval(() => {
            this.updateVitalSigns();
        }, 3000 + Math.random() * 2000); // Random between 3-5 seconds
    }

    generateMockPatient() {
        const firstNames = ['Jerry', 'George', 'Elaine', 'Cosmo', 'Newman', 'Susan', 'David', 'Frank'];
        const lastNames = ['Seinfeld', 'Costanza', 'Benes', 'Kramer', 'Newman', 'Ross', 'Puddy', 'Peterman'];
        const genders = ['Male', 'Female', 'Other'];
        const allergies = [null, 'Penicillin', 'Latex', 'Peanuts', 'Shellfish'];
        const reasons = ['Respiratory distress', 'Cardiac monitoring', 'Post-operative care', 'Infection treatment', 'Trauma recovery'];
        const wards = ['ICU-1', 'ICU-2', 'Surgical', 'Cardio', 'Oncology', 'Pediatrics'];
        
        const firstName = firstNames[Math.floor(Math.random() * firstNames.length)];
        const lastName = lastNames[Math.floor(Math.random() * lastNames.length)];
        const age = 25 + Math.floor(Math.random() * 60);
        const dob = new Date();
        dob.setFullYear(dob.getFullYear() - age);
        
        return {
            patientId: Math.floor(Math.random() * 1000) + 1,
            mrn: `MRN-${String(Math.floor(Math.random() * 999999)).padStart(6, '0')}`,
            firstName: firstName,
            lastName: lastName,
            age: age,
            dob: dob.toISOString().split('T')[0],
            gender: genders[Math.floor(Math.random() * genders.length)],
            contact: `555-${String(Math.floor(Math.random() * 10000)).padStart(4, '0')}`,
            allergies: allergies[Math.floor(Math.random() * allergies.length)],
            building: String.fromCharCode(65 + Math.floor(Math.random() * 5)), // A-E
            room: String(Math.floor(Math.random() * 100) + 1).padStart(3, '0'),
            bed: ['A', 'B'][Math.floor(Math.random() * 2)],
            ward: wards[Math.floor(Math.random() * wards.length)],
            admitDate: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000),
            reason: reasons[Math.floor(Math.random() * reasons.length)]
        };
    }

    generateMockVitals() {
        const now = new Date();
        now.setMinutes(now.getMinutes() - Math.floor(Math.random() * 30));
        
        const hr = 60 + Math.floor(Math.random() * 60);
        const spo2 = 90 + Math.floor(Math.random() * 10) + Math.random();
        const temp = 36 + Math.random() * 3;
        const systolic = 100 + Math.floor(Math.random() * 40);
        const diastolic = 60 + Math.floor(Math.random() * 30);
        
        return {
            heartRate: hr,
            bloodPressure: `${systolic}/${diastolic}`,
            spo2: spo2.toFixed(1),
            temperature: temp.toFixed(1),
            respiratory: 12 + Math.floor(Math.random() * 12),
            recordedAt: now,
            // Store raw values for continuous updates
            rawValues: {
                heartRate: hr,
                spo2: parseFloat(spo2.toFixed(1)),
                temperature: parseFloat(temp.toFixed(1)),
                respiratory: 12 + Math.floor(Math.random() * 12),
                systolic: systolic,
                diastolic: diastolic
            },
            // Flag abnormal values
            abnormal: {
                hr: hr < 60 || hr > 100,
                spo2: spo2 < 95,
                temp: temp < 36.5 || temp > 37.5
            }
        };
    }

    updateVitalSigns() {
        if (!this.currentPatient || !this.currentPatient.vitals) {
            return;
        }

        const vitals = this.currentPatient.vitals;
        const rawValues = vitals.rawValues;
        
        // Apply small realistic fluctuations to each vital sign
        // Heart Rate: ±1-3 bpm variation
        const hrChange = (Math.random() - 0.5) * 6; // -3 to +3
        rawValues.heartRate = Math.max(45, Math.min(180, rawValues.heartRate + hrChange));
        rawValues.heartRate = Math.round(rawValues.heartRate);
        
        // SpO2: ±0.1-0.3% variation (more stable)
        const spo2Change = (Math.random() - 0.5) * 0.6; // -0.3 to +0.3
        rawValues.spo2 = Math.max(85, Math.min(100, rawValues.spo2 + spo2Change));
        
        // Temperature: ±0.05-0.15°C variation (very stable)
        const tempChange = (Math.random() - 0.5) * 0.3; // -0.15 to +0.15
        rawValues.temperature = Math.max(35, Math.min(42, rawValues.temperature + tempChange));
        
        // Respiratory Rate: ±0-1 /min variation (fairly stable)
        if (Math.random() > 0.7) { // Only change occasionally
            const respChange = Math.round((Math.random() - 0.5) * 2); // -1 to +1
            rawValues.respiratory = Math.max(8, Math.min(30, rawValues.respiratory + respChange));
        }
        
        // Blood Pressure: ±1-3 mmHg variation
        const sysChange = Math.round((Math.random() - 0.5) * 6); // -3 to +3
        const diaChange = Math.round((Math.random() - 0.5) * 4); // -2 to +2
        rawValues.systolic = Math.max(80, Math.min(200, rawValues.systolic + sysChange));
        rawValues.diastolic = Math.max(40, Math.min(120, rawValues.diastolic + diaChange));
        
        // Update the displayed values
        vitals.heartRate = rawValues.heartRate;
        vitals.spo2 = rawValues.spo2.toFixed(1);
        vitals.temperature = rawValues.temperature.toFixed(1);
        vitals.respiratory = rawValues.respiratory;
        vitals.bloodPressure = `${rawValues.systolic}/${rawValues.diastolic}`;
        vitals.recordedAt = new Date();
        
        // Update abnormal flags
        vitals.abnormal = {
            hr: rawValues.heartRate < 60 || rawValues.heartRate > 100,
            spo2: rawValues.spo2 < 95,
            temp: rawValues.temperature < 36.5 || rawValues.temperature > 37.5
        };
        
        // Re-render vitals with animation
        this.renderVitalsWithAnimation(vitals);
        
        // Update alerts if any new abnormal values
        this.updateAlertsForVitals(vitals);
        
        // Occasionally add new dynamic content (5% chance each update)
        if (Math.random() < 0.05) {
            this.addDynamicHospitalContent();
        }
    }

    generateMockAlerts(vitals) {
        const alerts = [];
        
        if (vitals.abnormal.spo2) {
            alerts.push({
                type: vitals.spo2 < 88 ? 'Critical Low SpO2' : 'Low SpO2',
                severity: vitals.spo2 < 88 ? 'High' : 'Medium',
                message: `SpO2 level at ${vitals.spo2}% - below normal range`,
                createdAt: new Date(vitals.recordedAt.getTime() + 60000)
            });
        }
        
        if (vitals.abnormal.temp) {
            if (vitals.temperature > 38.5) {
                alerts.push({
                    type: vitals.temperature >= 39.5 ? 'High Fever' : 'Fever',
                    severity: vitals.temperature >= 39.5 ? 'High' : 'Medium',
                    message: `Temperature at ${vitals.temperature}°C - elevated`,
                    createdAt: new Date(vitals.recordedAt.getTime() + 30000)
                });
            }
        }
        
        if (vitals.abnormal.hr) {
            if (vitals.heartRate >= 120) {
                alerts.push({
                    type: vitals.heartRate >= 140 ? 'Tachycardia Severe' : 'Tachycardia',
                    severity: vitals.heartRate >= 140 ? 'High' : 'Medium',
                    message: `Heart rate at ${vitals.heartRate} bpm - elevated`,
                    createdAt: new Date(vitals.recordedAt.getTime() + 45000)
                });
            }
        }
        
        // Random additional alerts
        if (Math.random() > 0.7) {
            alerts.push({
                type: 'Lab Result Available',
                severity: 'Low',
                message: 'CBC panel results ready for review',
                createdAt: new Date(Date.now() - Math.random() * 3600000)
            });
        }
        
        return alerts;
    }

    generateMockCareTeam() {
        const providers = [
            { name: 'Dr. Kramer', role: 'Intern', isPrimary: false },
            { name: 'Dr. Newman', role: 'Resident', isPrimary: false },
            { name: 'Dr. Art Vandelay', role: 'Associate', isPrimary: true },
            { name: 'Dr. Tim Whatley', role: 'Attending', isPrimary: false },
            { name: 'Dr. Martin Van Nostrand', role: 'Specialist', isPrimary: false }
        ];
        
        // Return 2-4 random providers, always including at least one
        const count = 2 + Math.floor(Math.random() * 3);
        const team = [];
        const used = new Set();
        
        while (team.length < count && team.length < providers.length) {
            const index = Math.floor(Math.random() * providers.length);
            if (!used.has(index)) {
                used.add(index);
                team.push(providers[index]);
            }
        }
        
        return team;
    }

    generateMockSymptoms() {
        const symptoms = [
            { code: 'Fever', description: 'Fever' },
            { code: 'Cough', description: 'Persistent cough' },
            { code: 'Dyspnea', description: 'Shortness of breath' },
            { code: 'ChestPain', description: 'Chest pain' },
            { code: 'Nausea', description: 'Nausea' },
            { code: 'Headache', description: 'Headache' },
            { code: 'Fatigue', description: 'Fatigue' },
            { code: 'Dizziness', description: 'Dizziness' }
        ];
        
        const count = Math.floor(Math.random() * 4) + 1;
        const selected = [];
        const used = new Set();
        
        while (selected.length < count && selected.length < symptoms.length) {
            const index = Math.floor(Math.random() * symptoms.length);
            if (!used.has(index)) {
                used.add(index);
                selected.push(symptoms[index]);
            }
        }
        
        return selected;
    }

    generateMockOrders(careTeam) {
        const orderTypes = [
            { type: 'Medication', details: ['IV ceftriaxone 1g q24h', 'Acetaminophen 650mg PO q6h PRN', 'Lisinopril 10mg PO daily'] },
            { type: 'Laboratory', details: ['CBC with differential', 'Basic metabolic panel', 'Blood culture x2', 'Urinalysis'] },
            { type: 'Imaging', details: ['Chest X-ray PA/Lateral', 'CT Abdomen/Pelvis with contrast', 'MRI Brain without contrast'] }
        ];
        
        const statuses = ['Pending', 'InProgress', 'Completed', 'Cancelled'];
        const orders = [];
        const count = Math.floor(Math.random() * 4) + 2;
        
        for (let i = 0; i < count; i++) {
            const orderType = orderTypes[Math.floor(Math.random() * orderTypes.length)];
            const detail = orderType.details[Math.floor(Math.random() * orderType.details.length)];
            const hoursAgo = Math.random() * 48;
            const provider = careTeam[Math.floor(Math.random() * careTeam.length)];
            
            orders.push({
                type: orderType.type,
                details: detail,
                status: statuses[Math.floor(Math.random() * statuses.length)],
                orderedAt: new Date(Date.now() - hoursAgo * 3600000),
                provider: provider.name
            });
        }
        
        return orders.sort((a, b) => b.orderedAt - a.orderedAt);
    }

    generateMockNotes(careTeam) {
        const templates = [
            'Initial assessment completed. Patient stable and oriented. Monitoring vital signs closely.',
            'Lab results reviewed. WBC slightly elevated. Continue current antibiotic regimen.',
            'Patient reports improvement in symptoms. Pain well controlled. Plan to reassess in AM.',
            'Imaging results pending. Discussed treatment plan with patient and family.',
            'Medication adjusted per protocol. Tolerating PO intake. Continue monitoring.',
            'Physical therapy evaluation completed. Patient making progress with mobility.',
            'Vital signs trending in right direction. Consider step-down to regular floor if continues.'
        ];
        
        const notes = [];
        const count = Math.floor(Math.random() * 3) + 2;
        
        for (let i = 0; i < count; i++) {
            const hoursAgo = Math.random() * 36;
            const provider = careTeam[Math.floor(Math.random() * careTeam.length)];
            
            notes.push({
                text: templates[Math.floor(Math.random() * templates.length)],
                provider: provider.name,
                createdAt: new Date(Date.now() - hoursAgo * 3600000)
            });
        }
        
        return notes.sort((a, b) => b.createdAt - a.createdAt);
    }

    loadMockData(silent = false) {
        console.log('Loading patient data...', silent);
        if (!silent) {
            this.showLoading();
        }

        // Simulate API delay
        setTimeout(() => {
            try {
                console.log('Generating patient data...');
                // Generate complete patient data
                const patient = this.generateMockPatient();
                patient.vitals = this.generateMockVitals();
                patient.careTeam = this.generateMockCareTeam();
                patient.symptoms = this.generateMockSymptoms();
                patient.orders = this.generateMockOrders(patient.careTeam);
                patient.notes = this.generateMockNotes(patient.careTeam);
                patient.alerts = this.generateMockAlerts(patient.vitals);
                
                this.currentPatient = patient;
                console.log('Patient data generated:', patient);
                
                this.renderPatientData();
                console.log('Patient data rendered');
                
                // Start vital signs simulation after first successful load
                if (!this.vitalsInterval) {
                    this.startVitalSignsSimulation();
                }
                
                if (!silent) {
                    this.hideLoading();
                    console.log('Loading hidden');
                }
            } catch (error) {
                console.error('Error loading patient data:', error);
                this.showDebugError('Error in loadMockData', error);
                this.showToast('Error loading patient data: ' + error.message, true);
            }
        }, silent ? 100 : 1000);
    }

    renderPatientData() {
        console.log('Starting renderPatientData...');
        const patient = this.currentPatient;
        
        if (!patient) {
            console.error('No patient data to render!');
            throw new Error('No patient data available');
        }
        
        console.log('Rendering patient:', patient);
        
        try {
            // Header info
            document.getElementById('roomNumber').textContent = patient.room;
            document.getElementById('bedNumber').textContent = patient.bed;
            
            // Patient info
            document.getElementById('patientName').textContent = `${patient.firstName} ${patient.lastName}`;
            document.getElementById('patientAge').textContent = `${patient.age} years`;
            document.getElementById('patientGender').textContent = patient.gender;
            document.getElementById('patientMRN').textContent = `MRN: ${patient.mrn}`;
            document.getElementById('patientDOB').textContent = this.formatDate(patient.dob);
            document.getElementById('patientContact').textContent = patient.contact;
            document.getElementById('admitDate').textContent = this.formatDateTime(patient.admitDate);
            document.getElementById('admitReason').textContent = patient.reason;
            
            // Allergies
            if (patient.allergies) {
                document.getElementById('allergiesRow').style.display = 'flex';
                document.getElementById('allergies').textContent = patient.allergies;
            } else {
                document.getElementById('allergiesRow').style.display = 'none';
            }
            
            // Vitals
            this.renderVitals(patient.vitals);
            
            // Alerts
            this.renderAlerts(patient.alerts);
            
            // Care team
            this.renderCareTeam(patient.careTeam);
            
            // Symptoms
            this.renderSymptoms(patient.symptoms);
            
            // Orders
            this.renderOrders(patient.orders);
            
            // Notes
            this.renderNotes(patient.notes);
            
            console.log('Finished rendering patient data');
        } catch (error) {
            console.error('Error in renderPatientData:', error);
            throw error;
        }
    }

    renderVitals(vitals) {
        document.getElementById('heartRate').textContent = vitals.heartRate;
        document.getElementById('bloodPressure').textContent = vitals.bloodPressure;
        document.getElementById('spo2').textContent = vitals.spo2;
        document.getElementById('temperature').textContent = vitals.temperature;
        document.getElementById('respiratory').textContent = vitals.respiratory;
        document.getElementById('vitalsTime').textContent = this.formatTime(vitals.recordedAt);
        
        // Highlight abnormal values
        this.highlightAbnormal('heartRate', vitals.abnormal.hr);
        this.highlightAbnormal('spo2', vitals.abnormal.spo2);
        this.highlightAbnormal('temperature', vitals.abnormal.temp);
    }

    renderVitalsWithAnimation(vitals) {
        // Add subtle animation when vitals update
        const elements = ['heartRate', 'bloodPressure', 'spo2', 'temperature', 'respiratory'];
        
        elements.forEach(elementId => {
            const element = document.getElementById(elementId);
            if (element) {
                // Add update animation class
                element.classList.add('vital-update');
                
                // Remove the class after animation completes
                setTimeout(() => {
                    element.classList.remove('vital-update');
                }, 300);
            }
        });
        
        // Update values
        document.getElementById('heartRate').textContent = vitals.heartRate;
        document.getElementById('bloodPressure').textContent = vitals.bloodPressure;
        document.getElementById('spo2').textContent = vitals.spo2;
        document.getElementById('temperature').textContent = vitals.temperature;
        document.getElementById('respiratory').textContent = vitals.respiratory;
        document.getElementById('vitalsTime').innerHTML = `<span class="live-indicator">${this.formatTime(vitals.recordedAt)} Live</span>`;
        
        // Highlight abnormal values
        this.highlightAbnormal('heartRate', vitals.abnormal.hr);
        this.highlightAbnormal('spo2', vitals.abnormal.spo2);
        this.highlightAbnormal('temperature', vitals.abnormal.temp);
    }

    updateAlertsForVitals(vitals) {
        // Generate new alerts based on current vitals
        const newAlerts = this.generateMockAlerts(vitals);
        
        // Only update if there are new critical alerts
        const criticalAlerts = newAlerts.filter(alert => 
            alert.severity === 'High' || alert.severity === 'Critical'
        );
        
        if (criticalAlerts.length > 0) {
            // Add new alerts to existing ones (but don't duplicate)
            const existingAlertTypes = this.currentPatient.alerts.map(a => a.type);
            const genuinelyNewAlerts = criticalAlerts.filter(alert => 
                !existingAlertTypes.includes(alert.type)
            );
            
            if (genuinelyNewAlerts.length > 0) {
                this.currentPatient.alerts = [...genuinelyNewAlerts, ...this.currentPatient.alerts];
                this.renderAlerts(this.currentPatient.alerts);
            }
        }
    }

    addDynamicHospitalContent() {
        if (!this.currentPatient) return;

        const contentType = Math.random();
        
        if (contentType < 0.4) {
            // Add new lab result or completed lab order
            this.addNewLabResult();
        } else if (contentType < 0.7) {
            // Add new medication order or nursing order
            this.addNewOrder();
        } else {
            // Add new clinical note
            this.addNewNote();
        }
    }

    addNewLabResult() {
        const labResults = [
            'CBC with differential - COMPLETED',
            'Basic metabolic panel - COMPLETED',
            'Liver function panel - COMPLETED',
            'Lipid panel - COMPLETED',
            'Thyroid function tests - COMPLETED',
            'Urinalysis - COMPLETED',
            'Blood culture x2 - COMPLETED',
            'Troponin I - COMPLETED',
            'BNP - COMPLETED',
            'HbA1c - COMPLETED'
        ];

        const newLabOrder = {
            type: 'Laboratory',
            details: labResults[Math.floor(Math.random() * labResults.length)],
            status: 'Completed',
            orderedAt: new Date(),
            provider: this.currentPatient.careTeam[Math.floor(Math.random() * this.currentPatient.careTeam.length)].name
        };

        // Add to beginning of orders array
        this.currentPatient.orders.unshift(newLabOrder);
        this.renderOrders(this.currentPatient.orders);
        
        // Show notification
        this.showToast(`📊 ${newLabOrder.details}`, false);
    }

    addNewOrder() {
        const newOrders = [
            { type: 'Medication', details: 'Furosemide 40mg PO daily' },
            { type: 'Medication', details: 'Metoprolol 25mg PO BID' },
            { type: 'Medication', details: 'Insulin sliding scale per protocol' },
            { type: 'Laboratory', details: 'Morning labs: BMP, CBC' },
            { type: 'Laboratory', details: 'PT/PTT, INR' },
            { type: 'Imaging', details: 'Echocardiogram' },
            { type: 'Imaging', details: 'Ultrasound abdomen' },
            { type: 'Nursing', details: 'I&O monitoring q4h' },
            { type: 'Nursing', details: 'Glucose monitoring q6h' },
            { type: 'Therapy', details: 'Physical therapy evaluation' }
        ];

        const randomOrder = newOrders[Math.floor(Math.random() * newOrders.length)];
        const newOrder = {
            type: randomOrder.type,
            details: randomOrder.details,
            status: 'Pending',
            orderedAt: new Date(),
            provider: this.currentPatient.careTeam[Math.floor(Math.random() * this.currentPatient.careTeam.length)].name
        };

        // Add to beginning of orders array
        this.currentPatient.orders.unshift(newOrder);
        this.renderOrders(this.currentPatient.orders);
        
        // Show notification
        this.showToast(`📋 New ${newOrder.type}: ${newOrder.details}`, false);
    }

    addNewNote() {
        const newNoteTemplates = [
            'Patient responded well to treatment. Vital signs stable.',
            'Lab values reviewed. Continue current management plan.',
            'Patient ambulating with assistance. Pain level 3/10.',
            'Family meeting scheduled for discharge planning discussion.',
            'Respiratory status improved. Consider weaning oxygen support.',
            'Blood pressure well controlled on current medications.',
            'Patient education provided regarding discharge medications.',
            'Wound healing appropriately. Dressing changed and clean.',
            'Sleep pattern improving. Patient reports feeling more rested.',
            'Appetite increasing. Tolerating regular diet without issues.'
        ];

        const newNote = {
            text: newNoteTemplates[Math.floor(Math.random() * newNoteTemplates.length)],
            provider: this.currentPatient.careTeam[Math.floor(Math.random() * this.currentPatient.careTeam.length)].name,
            createdAt: new Date()
        };

        // Add to beginning of notes array
        this.currentPatient.notes.unshift(newNote);
        this.renderNotes(this.currentPatient.notes);
        
        // Show notification
        this.showToast(`📝 New note from ${newNote.provider}`, false);
    }

    highlightAbnormal(elementId, isAbnormal) {
        const element = document.getElementById(elementId);
        if (isAbnormal) {
            element.style.color = 'var(--danger-red)';
            element.style.fontWeight = '900';
        } else {
            element.style.color = '';
            element.style.fontWeight = '';
        }
    }

    renderAlerts(alerts) {
        const alertsCard = document.getElementById('alertsCard');
        const alertsList = document.getElementById('alertsList');
        
        if (alerts.length === 0) {
            alertsCard.style.display = 'none';
            return;
        }
        
        alertsCard.style.display = 'block';
        alertsList.innerHTML = alerts.map(alert => `
            <div class="alert-item ${alert.severity.toLowerCase()}">
                <div class="alert-icon">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 2L1 21h22L12 2zm0 3.83L19.53 19H4.47L12 5.83zM11 16h2v2h-2v-2zm0-6h2v4h-2v-4z"/>
                    </svg>
                </div>
                <div class="alert-content">
                    <div class="alert-type">${alert.type}</div>
                    <div class="alert-message">${alert.message}</div>
                    <div class="alert-time">${this.formatRelativeTime(alert.createdAt)}</div>
                </div>
            </div>
        `).join('');
    }

    renderCareTeam(team) {
        const container = document.getElementById('careTeam');
        container.innerHTML = team.map(member => {
            const initials = member.name.split(' ').map(n => n[0]).join('');
            return `
                <div class="team-member">
                    <div class="team-avatar">${initials}</div>
                    <div class="team-info">
                        <div class="team-name">${member.name}</div>
                        <div class="team-role">${member.role}</div>
                    </div>
                    ${member.isPrimary ? '<span class="team-badge">Primary</span>' : ''}
                </div>
            `;
        }).join('');
    }

    renderSymptoms(symptoms) {
        const container = document.getElementById('symptomsList');
        if (symptoms.length === 0) {
            container.innerHTML = '<div class="symptom-empty">No symptoms reported</div>';
            return;
        }
        
        container.innerHTML = symptoms.map(symptom => `
            <div class="symptom-tag">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                    <circle cx="12" cy="12" r="10"/>
                </svg>
                ${symptom.description}
            </div>
        `).join('');
    }

    renderOrders(orders) {
        const container = document.getElementById('ordersList');
        container.innerHTML = orders.slice(0, 5).map((order, index) => {
            const isNew = index === 0 && this.isRecentItem(order.orderedAt);
            return `
                <div class="order-item ${isNew ? 'new-item' : ''}">
                    <div class="order-header">
                        <div class="order-type">${order.type}</div>
                        <div class="order-status ${order.status.toLowerCase()}">${order.status}</div>
                    </div>
                    <div class="order-details">${order.details}</div>
                    <div class="order-footer">
                        <span>${order.provider}</span>
                        <span>${this.formatRelativeTime(order.orderedAt)}</span>
                    </div>
                </div>
            `;
        }).join('');
        
        // Remove new-item class after animation completes
        setTimeout(() => {
            const newItems = container.querySelectorAll('.new-item');
            newItems.forEach(item => item.classList.remove('new-item'));
        }, 1500);
    }

    renderNotes(notes) {
        const container = document.getElementById('notesList');
        container.innerHTML = notes.slice(0, 4).map((note, index) => {
            const isNew = index === 0 && this.isRecentItem(note.createdAt);
            return `
                <div class="note-item ${isNew ? 'new-item' : ''}">
                    <div class="note-header">
                        <div class="note-provider">${note.provider}</div>
                        <div class="note-time">${this.formatRelativeTime(note.createdAt)}</div>
                    </div>
                    <div class="note-text">${note.text}</div>
                </div>
            `;
        }).join('');
        
        // Remove new-item class after animation completes
        setTimeout(() => {
            const newItems = container.querySelectorAll('.new-item');
            newItems.forEach(item => item.classList.remove('new-item'));
        }, 1500);
    }

    // Utility functions
    formatDate(dateString) {
        const date = new Date(dateString);
        return date.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'short', 
            day: 'numeric' 
        });
    }

    formatDateTime(date) {
        return date.toLocaleString('en-US', { 
            month: 'short', 
            day: 'numeric', 
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    formatTime(date) {
        return date.toLocaleTimeString('en-US', { 
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    formatRelativeTime(date) {
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);
        
        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins} min ago`;
        if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
        return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
    }

    isRecentItem(date) {
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        return diffMins < 2; // Consider items from last 2 minutes as "new"
    }

    showAiModal() {
        const modal = document.getElementById('aiModal');
        modal.classList.add('show');
    }

    hideAiModal() {
        const modal = document.getElementById('aiModal');
        modal.classList.remove('show');
    }

    orderXray() {
        // Add X-ray order to the current patient's orders
        if (this.currentPatient && this.currentPatient.orders) {
            const newOrder = {
                type: 'Imaging',
                details: 'Chest X-ray PA/Lateral (AI Recommended)',
                status: 'Pending',
                orderedAt: new Date(),
                provider: 'AI Health Assistant'
            };
            
            // Add to beginning of orders array
            this.currentPatient.orders.unshift(newOrder);
            
            // Re-render orders
            this.renderOrders(this.currentPatient.orders);
            
            // Show success message
            this.showToast('✓ Chest X-ray ordered successfully', false);
            
            // Close modal
            this.hideAiModal();
        }
    }

    showDebugError(context, error) {
        const debugInfo = document.getElementById('debugInfo');
        const debugText = document.getElementById('debugText');
        if (debugInfo && debugText) {
            debugInfo.style.display = 'block';
            debugText.textContent = `Context: ${context}\n\nError: ${error.message}\n\nStack:\n${error.stack}`;
        }
        // Don't hide the loading overlay so the debug info stays visible
    }

    showLoading() {
        document.getElementById('loadingOverlay').classList.remove('hidden');
    }

    hideLoading() {
        document.getElementById('loadingOverlay').classList.add('hidden');
    }

    showToast(message, isError = false) {
        const toast = document.getElementById('errorToast');
        const messageEl = document.getElementById('errorMessage');
        messageEl.textContent = message;
        toast.classList.add('show');
        
        // Keep error messages visible longer (10 seconds), success messages shorter
        const duration = isError ? 10000 : 3000;
        setTimeout(() => {
            toast.classList.remove('show');
        }, duration);
    }

    cleanup() {
        // Clear intervals when app is destroyed
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
        if (this.vitalsInterval) {
            clearInterval(this.vitalsInterval);
            this.vitalsInterval = null;
        }
    }
}

// Initialize the app when DOM is ready
console.log('Setting up DOMContentLoaded listener...');
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM Content Loaded! Creating app instance...');
    try {
        const app = new PatientChartApp();
        console.log('App instance created:', app);
    } catch (error) {
        console.error('Failed to create app instance:', error);
        // Try to hide loading overlay even if app fails
        const overlay = document.getElementById('loadingOverlay');
        if (overlay) {
            overlay.classList.add('hidden');
        }
    }
});