const queryInput = document.getElementById("QueryText");
const examples = document.getElementById("SearchExample");
if (queryInput && examples) {
    examples.addEventListener("change", () => {
        const question = examples.selectedOptions[0]?.dataset.question;
        if (question) {
            queryInput.value = question;
            queryInput.focus();
        }
    });
    queryInput.addEventListener("input", () => {
        examples.value = Array.from(examples.options)
            .find(option => option.dataset.question === queryInput.value.trim())?.value ?? "";
    });
}
const searchResults = document.getElementById("search-results");
if (searchResults) {
    searchResults.focus({ preventScroll: true });
    searchResults.scrollIntoView({ block: "start" });
}
