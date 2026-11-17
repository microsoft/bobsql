namespace CaldovaNetworkScheduling.Services;

/// <summary>Illustrative staff seats, patients, and services shared by the scripted and measured scenes.</summary>
public static class ClinicCast
{
    public static readonly (string Role, string Location)[] Seats =
    [
        ("Front desk", "Main Campus"),
        ("Call center", "Patient Access"),
        ("Referral coordinator", "Heart Institute"),
        ("Nurse navigator", "Westside Clinic"),
        ("Front desk", "Pediatrics"),
        ("Call center", "Patient Access"),
        ("Surgical coordinator", "Orthopedic Center"),
        ("Front desk", "Lakeshore Clinic"),
    ];

    public static readonly string[] Patients =
    [
        "J. Rivera", "M. Chen", "A. Okoye", "S. Novak", "L. Haddad", "R. Patel", "E. Johansson",
        "T. Nguyen", "K. Mensah", "D. Rossi", "P. Kowalski", "H. Tanaka", "C. Duarte", "B. Schmidt",
        "N. Ibrahim", "G. Lindqvist", "F. Moreau", "Y. Sato", "O. Byrne", "V. Costa",
    ];

    public static readonly (string Specialty, string Clinic)[] Services =
    [
        ("Cardiology", "Heart Institute"),
        ("Orthopedics", "Orthopedic Center"),
        ("Pediatrics", "Pediatrics"),
        ("Primary Care", "Main Campus"),
        ("Primary Care", "Westside Clinic"),
        ("Dermatology", "Lakeshore Clinic"),
    ];

    public static string FutureSlot(Random random)
    {
        var day = DateTime.Today.AddDays(1 + random.Next(20));
        if (day.DayOfWeek == DayOfWeek.Saturday) day = day.AddDays(2);
        if (day.DayOfWeek == DayOfWeek.Sunday) day = day.AddDays(1);
        var slot = day.AddHours(8).AddMinutes(30 * random.Next(18));
        return slot.ToString("ddd MMM d · h:mm tt");
    }
}
