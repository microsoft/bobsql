// Clinical Search Application - JavaScript
// Zava Hospital Training System

// Mock data for demonstration (matches the example results provided)
const mockResults = [
    { Symptom: "Fever", EncounterReason: "Infection", HeartRate: 105, BloodPressure: "106/86", TemperatureC: 39.1, RespiratoryRate: 17, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Fever", EncounterReason: "Infection", HeartRate: 123, BloodPressure: "111/72", TemperatureC: 36.7, RespiratoryRate: 10, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Fever", EncounterReason: "Infection", HeartRate: 55, BloodPressure: "101/58", TemperatureC: 35.9, RespiratoryRate: 27, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Fever", EncounterReason: "Infection", HeartRate: 117, BloodPressure: "138/93", TemperatureC: 38.8, RespiratoryRate: 23, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Fever", EncounterReason: "Infection", HeartRate: 113, BloodPressure: "144/57", TemperatureC: 38.7, RespiratoryRate: 17, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 105, BloodPressure: "106/86", TemperatureC: 39.1, RespiratoryRate: 17, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 123, BloodPressure: "111/72", TemperatureC: 36.7, RespiratoryRate: 10, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 55, BloodPressure: "101/58", TemperatureC: 35.9, RespiratoryRate: 27, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 117, BloodPressure: "138/93", TemperatureC: 38.8, RespiratoryRate: 23, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 113, BloodPressure: "144/57", TemperatureC: 38.7, RespiratoryRate: 17, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 123, BloodPressure: "123/85", TemperatureC: 37.8, RespiratoryRate: 10, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 83, BloodPressure: "119/64", TemperatureC: 36.5, RespiratoryRate: 27, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 113, BloodPressure: "100/80", TemperatureC: 37.6, RespiratoryRate: 17, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 112, BloodPressure: "122/84", TemperatureC: 37.0, RespiratoryRate: 24, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 103, BloodPressure: "148/70", TemperatureC: 36.3, RespiratoryRate: 24, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 100, BloodPressure: "139/70", TemperatureC: 38.3, RespiratoryRate: 21, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 103, BloodPressure: "127/62", TemperatureC: 37.2, RespiratoryRate: 16, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Shortness of breath", EncounterReason: "Infection", HeartRate: 123, BloodPressure: "113/77", TemperatureC: 36.0, RespiratoryRate: 19, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Sore throat", EncounterReason: "Infection", HeartRate: 123, BloodPressure: "123/85", TemperatureC: 37.8, RespiratoryRate: 10, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." },
    { Symptom: "Sore throat", EncounterReason: "Infection", HeartRate: 83, BloodPressure: "119/64", TemperatureC: 36.5, RespiratoryRate: 27, OrderDetails: "Chest X-ray PA/LAT", NoteText: "Follow-up evaluation. Peripheral edema trace; de-escalate antibiotics if afebrile. Care team updated." }
];

// DOM Elements
const searchInput = document.getElementById('searchInput');
const searchButton = document.getElementById('searchButton');
const resultsSection = document.getElementById('resultsSection');
const resultsContainer = document.getElementById('resultsContainer');
const resultsCount = document.getElementById('resultsCount');
const loadingOverlay = document.getElementById('loadingOverlay');
const exportButton = document.getElementById('exportButton');
const exampleChips = document.querySelectorAll('.example-chip');

// Parameters
const returnTopNInput = document.getElementById('returnTopN');
const searchTopNInput = document.getElementById('searchTopN');
const maxDistanceInput = document.getElementById('maxDistance');

// Auto-populate the example query on page load
window.addEventListener('DOMContentLoaded', () => {
    searchInput.value = 'patient with shortness of breath with fever and IV antibiotics';
});

// Event Listeners
searchButton.addEventListener('click', performSearch);
searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        performSearch();
    }
});

exampleChips.forEach(chip => {
    chip.addEventListener('click', () => {
        const query = chip.getAttribute('data-query');
        searchInput.value = query;
        performSearch();
    });
});

exportButton.addEventListener('click', exportResults);

// Main Search Function
async function performSearch() {
    const query = searchInput.value.trim();
    
    if (!query) {
        alert('Please enter a search query');
        return;
    }

    // Show loading overlay
    showLoading(true);

    // Simulate API delay (in production, this would call the actual stored procedure)
    await simulateApiCall(1500);

    // In production, you would call your backend API here:
    // const results = await callVectorSearchAPI(query, getSearchParams());
    
    // For demo purposes, use mock data
    const results = mockResults;

    // Display results
    displayResults(results, query);

    // Hide loading overlay
    showLoading(false);
}

// Simulate API Call
function simulateApiCall(delay) {
    return new Promise(resolve => setTimeout(resolve, delay));
}

// Get Search Parameters
function getSearchParams() {
    return {
        returnTopN: parseInt(returnTopNInput.value) || 20,
        searchTopN: parseInt(searchTopNInput.value) || 10,
        maxDistance: parseFloat(maxDistanceInput.value) || 0.45
    };
}

// Display Results
function displayResults(results, query) {
    resultsContainer.innerHTML = '';
    
    if (results.length === 0) {
        resultsContainer.innerHTML = `
            <div style="text-align: center; padding: 3rem; color: var(--text-secondary);">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" style="margin-bottom: 1rem;">
                    <circle cx="11" cy="11" r="8"></circle>
                    <path d="m21 21-4.35-4.35"></path>
                </svg>
                <h3>No results found</h3>
                <p>Try adjusting your search query or parameters</p>
            </div>
        `;
        resultsSection.style.display = 'block';
        resultsCount.textContent = '0 cases found';
        return;
    }

    results.forEach((result, index) => {
        const card = createResultCard(result, index + 1);
        resultsContainer.appendChild(card);
    });

    resultsSection.style.display = 'block';
    resultsCount.textContent = `${results.length} case${results.length !== 1 ? 's' : ''} found`;
}

// Create Result Card
function createResultCard(result, number) {
    const card = document.createElement('div');
    card.className = 'result-card';
    
    const tempF = (result.TemperatureC * 9/5) + 32;
    
    card.innerHTML = `
        <div class="result-header">
            <div class="result-badges">
                <span class="badge badge-symptom">${escapeHtml(result.Symptom)}</span>
                <span class="badge badge-reason">${escapeHtml(result.EncounterReason)}</span>
            </div>
            <span class="result-number">Case #${number}</span>
        </div>
        
        <div class="result-vitals">
            <div class="vital-item">
                <span class="vital-label">Heart Rate</span>
                <span class="vital-value">${result.HeartRate} bpm</span>
            </div>
            <div class="vital-item">
                <span class="vital-label">Blood Pressure</span>
                <span class="vital-value">${escapeHtml(result.BloodPressure)}</span>
            </div>
            <div class="vital-item">
                <span class="vital-label">Temperature</span>
                <span class="vital-value">${result.TemperatureC}°C (${tempF.toFixed(1)}°F)</span>
            </div>
            <div class="vital-item">
                <span class="vital-label">Respiratory Rate</span>
                <span class="vital-value">${result.RespiratoryRate} /min</span>
            </div>
        </div>
        
        <div class="result-details">
            <div class="detail-section">
                <div class="detail-label">Order Details</div>
                <div class="detail-value">${escapeHtml(result.OrderDetails)}</div>
            </div>
            <div class="detail-section">
                <div class="detail-label">Clinical Notes</div>
                <div class="detail-value">${escapeHtml(result.NoteText)}</div>
            </div>
        </div>
    `;
    
    return card;
}

// Show/Hide Loading
function showLoading(show) {
    loadingOverlay.style.display = show ? 'flex' : 'none';
}

// Export Results to CSV
function exportResults() {
    const results = mockResults; // In production, use the actual search results
    
    if (results.length === 0) {
        alert('No results to export');
        return;
    }

    // Create CSV content
    const headers = ['Symptom', 'Encounter Reason', 'Heart Rate', 'Blood Pressure', 'Temperature (C)', 'Respiratory Rate', 'Order Details', 'Clinical Notes'];
    const csvContent = [
        headers.join(','),
        ...results.map(r => [
            `"${r.Symptom}"`,
            `"${r.EncounterReason}"`,
            r.HeartRate,
            `"${r.BloodPressure}"`,
            r.TemperatureC,
            r.RespiratoryRate,
            `"${r.OrderDetails}"`,
            `"${r.NoteText}"`
        ].join(','))
    ].join('\n');

    // Create download link
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    
    link.setAttribute('href', url);
    link.setAttribute('download', `clinical-search-results-${new Date().toISOString().slice(0, 10)}.csv`);
    link.style.visibility = 'hidden';
    
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

// Utility function to escape HTML
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// In production, this would be your API call function:
/*
async function callVectorSearchAPI(prompt, params) {
    try {
        const response = await fetch('/api/search/clinical-cases', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                prompt: prompt,
                returnTopN: params.returnTopN,
                searchTopN: params.searchTopN,
                maxDistance: params.maxDistance
            })
        });

        if (!response.ok) {
            throw new Error('Search failed');
        }

        const data = await response.json();
        return data.results;
    } catch (error) {
        console.error('Error calling vector search API:', error);
        alert('An error occurred while searching. Please try again.');
        return [];
    }
}
*/

console.log('Zava Clinical Search App - Ready');
