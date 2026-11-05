# ZavaHealth Digital Patient Chart

A modern, Figma-inspired web application designed for hospital room digital displays. This bedside patient chart provides real-time clinical information for healthcare providers and patients.

## 🎯 Overview

This application simulates a digital chart that would be displayed on a tablet or screen next to a patient's bed in a hospital. It shows comprehensive patient information including vitals, alerts, care team, medications, and clinical notes in an intuitive, easy-to-read format.

## ✨ Features

### Patient Information
- **Patient Demographics**: Name, age, gender, MRN, date of birth
- **Admission Details**: Admit date, reason for admission, current location (room/bed)
- **Allergy Alerts**: Prominent display of patient allergies with visual warning

### Clinical Data
- **Live Vital Signs Monitoring**:
  - Heart Rate (BPM) - Updates every 3-5 seconds with ±1-3 bpm variation
  - Blood Pressure (mmHg) - Realistic ±1-3 mmHg fluctuations
  - SpO₂ (Oxygen Saturation %) - Stable ±0.1-0.3% variation like real pulse oximeters
  - Temperature (°C) - Very stable ±0.05-0.15°C variation like real thermometers
  - Respiratory Rate (/min) - Occasional ±0-1 /min changes
  - Live indicator with blinking green dot showing real-time monitoring
  - Visual highlighting of abnormal values with pulse animation
  - Automatic alert generation when values cross danger thresholds

- **Active Alerts**: 
  - Critical, high, medium, and low severity alerts
  - Auto-generated based on vital sign thresholds
  - Timestamped with relative time display

- **Care Team**:
  - Provider names with roles (Intern, Resident, Associate, Attending)
  - Primary care provider designation
  - Visual avatars with initials

- **Current Symptoms**:
  - Visual tags for active symptoms
  - Easy-to-scan layout

- **Dynamic Recent Orders**:
  - Real-time addition of new medication, laboratory, and imaging orders
  - Completed lab results appear automatically (CBC, BMP, cultures, etc.)
  - Status tracking (Pending, In Progress, Completed, Cancelled)
  - Provider attribution with automatic timestamps
  - Visual slide-in animations for new orders
  - Green highlighting for recently added items

- **Live Clinical Notes**:
  - Continuous addition of new provider notes throughout the day
  - Realistic clinical updates: treatment responses, assessments, care plans
  - Provider attribution with "Just now" timestamps for fresh notes
  - Chronological display with newest items first
  - Smooth visual feedback when new notes appear

## 🫀 Live Monitoring Features (Added November 2025)

### Real-time Vital Signs Simulation
- **Continuous Updates**: Vitals change every 3-5 seconds with randomized timing
- **Realistic Medical Device Simulation**: Each vital sign mimics actual monitoring equipment behavior:
  - **Heart Rate Monitor**: ±1-3 bpm natural variation
  - **Pulse Oximeter**: ±0.1-0.3% stable readings with occasional fluctuations
  - **Digital Thermometer**: ±0.05-0.15°C very stable temperature readings
  - **Respiratory Monitor**: Occasional ±0-1 /min changes
  - **Blood Pressure Cuff**: ±1-3 mmHg variation for systolic/diastolic

### Visual Feedback System
- **Pulse Animation**: Subtle scaling and background color change when vitals update
- **Live Indicator**: Green blinking dot with "Live" text showing active monitoring
- **Smart Value Highlighting**: Abnormal values automatically highlighted in red
- **Smooth Transitions**: 300ms animation duration for professional appearance

### Intelligent Alert Generation
- **Dynamic Thresholds**: Alerts generated based on medical standards:
  - SpO₂ < 92% (Medium alert), < 88% (High/Critical alert)
  - Temperature > 38.5°C (Medium), > 39.5°C (High alert)  
  - Heart Rate > 120 BPM (Medium), > 140 BPM (High alert)
- **No Alert Spam**: System prevents duplicate alerts for same conditions
- **Real-time Updates**: New critical alerts appear immediately when thresholds crossed

### Dynamic Hospital Content System
- **Realistic Workflow Simulation**: New orders, lab results, and clinical notes appear periodically
- **Smart Content Distribution**: 40% lab results, 30% new orders, 30% clinical notes
- **Authentic Hospital Operations**: Content mimics real hospital timing and workflow patterns
- **Visual Feedback**: New items appear with slide-in animations and green highlighting
- **Toast Notifications**: Unobtrusive alerts for new content (📊 labs, 📋 orders, 📝 notes)

## 🎨 Design Features

### Modern UI/UX
- **Figma-inspired Design**: Clean, professional interface with modern components
- **Color-coded Information**: Visual hierarchy using color psychology
  - Blue: Primary information and headers
  - Red: Critical alerts and allergies
  - Yellow: Warnings and symptoms
  - Green: Vitals, success states, and live indicators

### Responsive Layout
- **Two-column Grid**: Optimal information density
- **Smooth Animations**: Subtle transitions and hover effects
- **Card-based Design**: Organized content in digestible sections
- **Custom Scrollbars**: Styled for modern appearance

### Visual Elements
- **SVG Icons**: Scalable, crisp icons for all medical data
- **Status Badges**: Color-coded order and alert statuses
- **Avatar System**: Provider initials in circular avatars
- **Loading States**: Smooth loading overlay with spinner

## 🏗️ Architecture

### File Structure
```
zavahospital/
├── digital-chart.html    # Main HTML structure
├── digital-chart.css     # Comprehensive styling with CSS variables
└── digital-chart.js      # Application logic and data generation
```

### Data Model (Based on ZavaHealth Schema)

The application mirrors the database schema from `01_schema.sql` and `02_seeding.sql`:

#### Core Tables
- `core.Patients` - Patient demographics
- `core.BedAssignments` - Current bed location
- `core.Encounters` - Hospital admissions
- `core.Providers` - Care team members

#### Clinical Tables
- `clinical.VitalsSnapshots` - Vital sign measurements
- `clinical.DoctorNotes` - Provider documentation
- `clinical.Symptoms` - Current patient symptoms
- `clinical.Orders` - Treatment orders
- `clinical.Alerts` - Clinical alerts and warnings

#### Reference Tables
- `ref.Buildings` - Building A-E (North Richland Hills, TX)
- `ref.Rooms` - 100 rooms per building
- `ref.Beds` - 2 beds per room (A/B)
- `ref.ProviderRoles` - Intern, Resident, Associate, Attending, Consultant

## 🚀 Getting Started

### Prerequisites
- Modern web browser (Chrome, Firefox, Safari, Edge)
- No server required - runs entirely in the browser

### Installation

1. **Open the Application**:
   ```
   Simply open digital-chart.html in your web browser
   ```

2. **Or Use a Local Server** (optional):
   ```bash
   # Using Python
   python -m http.server 8000
   
   # Using Node.js (http-server)
   npx http-server
   ```

3. **Access the Application**:
   ```
   Open http://localhost:8000/digital-chart.html in your browser
   ```

## 💡 Usage

### Navigation
- **Refresh Button**: Manually refresh patient data
- **Settings Button**: Future configuration options
- **Auto-refresh**: Data automatically updates every 30 seconds

### Features in Action
- **Live Vital Monitoring**: Values update continuously every 3-5 seconds with realistic variations
- **Pulse Animations**: Subtle visual feedback when vital signs update with new readings
- **Live Indicator**: Green blinking dot shows active real-time monitoring status
- **Abnormal Vitals**: Values outside normal ranges are highlighted in red with enhanced visibility
- **Dynamic Alerts**: Generated automatically when vital signs cross medical thresholds
- **Smart Alert Management**: Prevents duplicate alerts while ensuring critical issues are visible
- **Hover Effects**: Cards and items respond to mouse hover for better interactivity
- **Responsive Design**: Layout adapts to different screen sizes

### Alert Thresholds
The system automatically generates alerts based on:
- **SpO₂**: < 92% (Medium), < 88% (High/Critical)
- **Temperature**: > 38.5°C (Medium), > 39.5°C (High)
- **Heart Rate**: > 120 BPM (Medium), > 140 BPM (High)

## 🎭 Mock Data

The application uses realistic mock data based on the Seinfeld character theme from the seeding script:

- **Patients**: Jerry Seinfeld, George Costanza, Elaine Benes, etc.
- **Providers**: Dr. Kramer (Intern) → Dr. Newman (Resident) → Dr. Art Vandelay (Associate)
- **Locations**: Buildings A-E, Rooms 001-100, Beds A-B
- **Wards**: ICU-1, ICU-2, Surgical, Cardio, Oncology, Pediatrics

## 🔧 Customization

### CSS Variables
Easily customize colors, spacing, and more by modifying CSS variables in `digital-chart.css`:

```css
:root {
    --primary-blue: #0078d4;
    --success-green: #10b981;
    --danger-red: #ef4444;
    --spacing-md: 16px;
    --radius-lg: 16px;
    /* ... and more */
}
```

### Mock Data
Modify data generation in `digital-chart.js`:
- Update patient names, vitals ranges, symptoms
- Adjust refresh intervals
- Customize alert thresholds

## 📱 Responsive Design

The application adapts to various screen sizes:
- **Desktop**: Two-column layout with full feature set
- **Tablet**: Stacked columns with grid-based sections
- **Mobile**: Single column with prioritized information

## 🖨️ Print Support

Print-friendly styles are included:
- Simplified layout for paper output
- Removes interactive elements
- High contrast for readability

## 🔐 Security Considerations

For production deployment:
1. **Connect to Real Database**: Replace mock data with secure API calls
2. **Authentication**: Implement user authentication and authorization
3. **HIPAA Compliance**: Ensure PHI protection and audit logging
4. **Row-Level Security**: Leverage the RLS policies in the database schema
5. **Encryption**: Use HTTPS and encrypt sensitive data

## 🚦 Future Enhancements

Potential additions:
- [ ] Real-time vitals streaming from medical devices
- [ ] Interactive charts and graphs (vitals trends)
- [ ] Medication administration tracking
- [ ] Nurse call integration
- [ ] Patient education content
- [ ] Family communication features
- [ ] Multilingual support
- [ ] Voice commands/accessibility features
- [ ] Integration with hospital EMR systems

## 📊 Database Integration

To connect to the actual ZavaHealth database:

1. **Set up Azure SQL Database** with the provided schema scripts
2. **Create API endpoints** to fetch:
   - Patient demographics and bed assignment
   - Latest vital signs
   - Active alerts
   - Care team assignments
   - Recent orders and notes
3. **Replace mock data functions** with API calls in `digital-chart.js`
4. **Implement WebSocket** for real-time vital signs updates

## 🏥 Use Cases

- **Patient Bedside**: Display next to patient bed for quick reference
- **Nursing Stations**: Multiple patient monitoring
- **Provider Rounds**: Quick patient overview during rounds
- **Patient/Family**: Share non-sensitive information with patients
- **Telehealth**: Remote patient monitoring display

## � Development Session Log - November 10, 2025

### Latest Enhancement Request
**User Prompt**: *"when the app comes up can you have the vitals change slightly like real monitoring devices are being updated on the chart?"*

### Implementation Summary
Successfully added realistic vital signs monitoring simulation to enhance the bedside chart experience:

#### Technical Changes Made:
1. **New Methods Added**:
   - `startVitalSignsSimulation()` - Initiates continuous vital updates
   - `updateVitalSigns()` - Applies realistic fluctuations to each vital sign
   - `renderVitalsWithAnimation()` - Updates display with visual feedback
   - `updateAlertsForVitals()` - Generates alerts for threshold violations
   - `cleanup()` - Proper interval management and memory cleanup

2. **Enhanced Data Structure**:
   - Added `rawValues` object to track continuous vital sign values
   - Implemented realistic variation ranges for each vital type
   - Maintained medical accuracy with appropriate bounds checking

3. **Visual Improvements**:
   - **CSS Animations**: Added `vital-pulse` keyframe for update feedback
   - **Live Indicator**: Blinking green dot with "Live" text
   - **Smooth Transitions**: 300ms animation duration for professional appearance

4. **Smart Alert System**:
   - Dynamic threshold monitoring for all vital signs
   - Prevents duplicate alert generation
   - Real-time alert creation when values become concerning

#### Medical Accuracy Features:
- **Heart Rate**: 45-180 BPM range with ±1-3 BPM natural variation
- **SpO₂**: 85-100% range with ±0.1-0.3% stable readings (mimics pulse oximetry)
- **Temperature**: 35-42°C range with ±0.05-0.15°C very stable readings
- **Respiratory Rate**: 8-30 /min range with occasional ±0-1 /min changes
- **Blood Pressure**: Realistic systolic (80-200) and diastolic (40-120) ranges

#### Performance Optimizations:
- **Separate Update Intervals**: Main refresh (30s) vs vital simulation (3-5s)
- **Memory Management**: Proper cleanup prevents interval leaks
- **Conditional Updates**: Vitals simulation starts only after successful data load
- **Efficient Rendering**: Minimal DOM updates with targeted element changes

### Result
The digital chart now provides a realistic bedside monitoring experience with:
- ✅ Continuous vital sign updates mimicking real medical devices
- ✅ Professional visual feedback with pulse animations
- ✅ Live monitoring indicator for clear status visibility  
- ✅ Intelligent alert generation based on medical thresholds
- ✅ Smooth, responsive user experience

## �📝 License

This is a demonstration application for ZavaHealth Hospital system.

## 👨‍⚕️ Credits

- Based on ZavaHealth Hospital Schema
- Seinfeld character theme for test data
- Modern healthcare UI/UX patterns
- Inspired by Figma design principles
- Live monitoring enhancement (November 2025)

---

**Note**: This is a demonstration application with mock data. For production use, integrate with actual medical systems and ensure compliance with healthcare regulations (HIPAA, HITECH, etc.).