document.querySelectorAll(".mask-help").forEach((help) => {
    help.addEventListener("pointerenter", () => {
        delete help.dataset.dismissed;
    });
    help.addEventListener("focusin", () => {
        delete help.dataset.dismissed;
    });
    help.addEventListener("pointerleave", () => {
        if (!help.contains(document.activeElement)) {
            delete help.dataset.dismissed;
        }
    });
    help.addEventListener("focusout", () => {
        if (!help.matches(":hover")) {
            delete help.dataset.dismissed;
        }
    });
});
document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
        document.querySelectorAll(".mask-help").forEach((help) => {
            help.dataset.dismissed = "true";
        });
    }
});
