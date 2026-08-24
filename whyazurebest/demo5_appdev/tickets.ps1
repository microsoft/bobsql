# Ten support tickets, one per triage outcome, so the agent visibly reasons
# rather than pattern-matching one canned answer. Dot-sourced by the bake-off
# and by the burst script.
#
# The last one ("It's broken") is deliberately useless: a good agent asks for
# more detail instead of inventing an action.

$script:Tickets = @(
    @{
        Customer = 'Contoso Manufacturing'
        Severity = 1
        Subject  = 'Checkout page returning 500'
        Body     = 'Customers cannot complete orders since the morning deploy. Error rate is 100 percent on the payment step.'
    },
    @{
        Customer = 'Wide World Importers'
        Severity = 1
        Subject  = 'Suspicious login attempts from an unknown region'
        Body     = 'Dozens of failed admin logins overnight from an IP range we do not operate in. No successful logins that we can see yet.'
    },
    @{
        Customer = 'Adventure Works'
        Severity = 2
        Subject  = 'Charged twice for the March subscription'
        Body     = 'Two identical charges hit the same card on the same day. Invoice numbers differ but the amounts match exactly.'
    },
    @{
        Customer = 'Fabrikam Logistics'
        Severity = 2
        Subject  = 'Warehouse scanner offline'
        Body     = 'Handheld scanners in bay 3 stopped reporting after the 06:00 sync. Bays 1 and 2 are fine.'
    },
    @{
        Customer = 'Fourth Coffee'
        Severity = 2
        Subject  = 'TLS certificate expires in five days'
        Body     = 'Our scanner flagged the API gateway certificate. Nothing is broken yet but it lapses on Friday.'
    },
    @{
        Customer = 'Litware Inc'
        Severity = 3
        Subject  = 'Reports load slowly between 2 and 4 pm'
        Body     = 'The dashboard takes about 40 seconds instead of 3, but only in the afternoon. It clears up by itself in the evening.'
    },
    @{
        Customer = 'Tailwind Traders'
        Severity = 3
        Subject  = 'Password reset email never arrives'
        Body     = 'Tried three times over an hour for one user. Checked the spam folder. Other users can reset normally.'
    },
    @{
        Customer = 'Proseware'
        Severity = 4
        Subject  = 'Please add dark mode to the portal'
        Body     = 'Our night shift finds the current theme hard on the eyes over a full shift.'
    },
    @{
        Customer = 'Northwind Traders'
        Severity = 4
        Subject  = 'How do I export my invoice history?'
        Body     = 'I need last quarter invoices as a CSV for our auditor. I cannot find the option in the portal.'
    },
    @{
        Customer = 'Alpine Ski House'
        Severity = 3
        Subject  = 'It is broken'
        Body     = 'Nothing works. Please fix.'
    }
)
