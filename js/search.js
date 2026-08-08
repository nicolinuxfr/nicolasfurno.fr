import * as pagefind from "/pagefind/pagefind.js";

const searchInput = document.getElementById("search-input");
const searchInputContainer = document.getElementById("search-input-container");
const searchResults = document.getElementById("search-results");
const searchFilters = document.getElementById("search-filters");
const searchSort = document.getElementById("search-sort");
const searchCategories = document.getElementById("search-categories");
const footer = document.querySelector(".footer");
const searchTerm = new URL(document.location).searchParams.get("s");
let searchNumber = 0;
let currentResults = [];
let termResults = [];
let activeCategory = null;
let sortMode = "relevance";
let currentTerm = null;

if (searchTerm) {
    searchInput.value = searchTerm;
}

function updateSearchURL(term) {
    const url = new URL(document.location);
    if (term) {
        url.searchParams.set("s", term);
    } else {
        url.searchParams.delete("s");
    }
    history.replaceState(null, "", url);
}

function focusResult(link) {
    link.focus({ preventScroll: true });
    link.scrollIntoView({ block: "center", inline: "nearest" });
}

new ResizeObserver(() => {
    document.documentElement.style.setProperty("--search-input-height", `${searchInputContainer.offsetHeight}px`);
}).observe(searchInputContainer);

function updateFilterPosition() {
    const footerTop = footer?.getBoundingClientRect().top ?? window.innerHeight;
    const clearance = Math.max(0, window.innerHeight - footerTop + 16);
    document.documentElement.style.setProperty("--search-footer-clearance", `${clearance}px`);
}

document.addEventListener("scroll", updateFilterPosition, { passive: true });
window.addEventListener("resize", updateFilterPosition);
updateFilterPosition();

async function searchExec(term) {
    term = term.trim();
    updateSearchURL(term);
    if (term === currentTerm) return;
    currentTerm = term;

    const currentSearch = ++searchNumber;
    searchResults.replaceChildren();
    requestAnimationFrame(updateFilterPosition);

        if (!term) {
            currentResults = [];
            termResults = [];
            activeCategory = null;
            updateFilters();
            return;
    }

    const results = await pagefind.search(term);
    if (currentSearch !== searchNumber) return;

        currentResults = await Promise.all(results.results.map(async (result, relevance) => {
            const data = await result.data();
        return {
            data,
            relevance,
            category: data.meta.category,
            date: Number(data.meta.date) || 0
            };
        }));
        termResults = currentResults;

    if (currentSearch === searchNumber) {
        activeCategory = null;
        sortMode = "relevance";
            updateFilters();
            renderResults();
    }
}

function renderResults() {
    let visibleResults = activeCategory
        ? currentResults.filter((result) => result.category === activeCategory)
        : [...currentResults];

    if (sortMode !== "relevance") {
        const direction = sortMode === "newest" ? -1 : 1;
        visibleResults.sort((a, b) => direction * (a.date - b.date) || a.relevance - b.relevance);
    }

    const items = [];
    let currentYear = null;

    visibleResults.forEach(({ data, date }) => {
        if (sortMode !== "relevance") {
            const year = date ? String(new Date(date * 1000).getFullYear()) : "Sans date";
            if (year !== currentYear) {
                const yearItem = document.createElement("li");
                const heading = document.createElement("h2");
                yearItem.className = "search-results-year";
                heading.textContent = year;
                yearItem.append(heading);
                items.push(yearItem);
                currentYear = year;
            }
        }

        const item = document.createElement("li");
        const link = document.createElement("a");
        link.href = data.url;
        link.textContent = data.meta.title;
        item.append(link);
        items.push(item);
    });

    searchResults.replaceChildren(...items);
    requestAnimationFrame(updateFilterPosition);
}

function updateFilters() {
    const sortLabels = {
        relevance: ["Pertinence", "Trier par date, du plus récent au plus ancien"],
        newest: ["Plus récents d’abord", "Trier par date, du plus ancien au plus récent"],
        oldest: ["Plus anciens d’abord", "Revenir au tri par pertinence"]
    };
    const [title, label] = sortLabels[sortMode];
    searchSort.title = title;
    searchSort.setAttribute("aria-label", label);
    searchSort.dataset.sort = sortMode;
    searchSort.classList.toggle("active", sortMode !== "relevance");

    const categoryCounts = termResults.reduce((counts, result) => {
        if (result.category) counts[result.category] = (counts[result.category] || 0) + 1;
        return counts;
    }, {});

    searchCategories.querySelectorAll("button[data-category]").forEach((button) => {
        const isActive = button.dataset.category === activeCategory;
        const count = currentTerm
            ? categoryCounts[button.dataset.category] || 0
            : Number(button.dataset.totalCount);
        const title = button.dataset.categoryTitle;
        button.hidden = Boolean(currentTerm) && count === 0;
        button.querySelector(".search-filter-count").textContent = count;
        button.setAttribute("aria-label", `${title}, ${count} résultat${count > 1 ? "s" : ""}`);
        button.classList.toggle("active", isActive);
        button.setAttribute("aria-pressed", String(isActive));
    });
}

searchSort.addEventListener("click", () => {
    sortMode = sortMode === "relevance" ? "newest" : sortMode === "newest" ? "oldest" : "relevance";
    updateFilters();
    renderResults();
    requestAnimationFrame(() => searchResults.scrollIntoView({ block: "start" }));
});

searchCategories.addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-category]");
    if (!button) return;

    if (activeCategory === button.dataset.category) {
        activeCategory = null;
        currentResults = termResults;
    } else if (currentTerm) {
        activeCategory = button.dataset.category;
        currentResults = termResults;
    } else {
        const currentSearch = ++searchNumber;
        const category = button.dataset.category;
        const results = await pagefind.search(null, { filters: { category } });
        if (currentSearch !== searchNumber) return;

        currentResults = await Promise.all(results.results.map(async (result, relevance) => {
            const data = await result.data();
            return {
                data,
                relevance,
                category: data.meta.category,
                date: Number(data.meta.date) || 0
            };
        }));
        activeCategory = category;
    }

    updateFilters();
    renderResults();
});

if (searchTerm) {
    searchExec(searchTerm);
}

searchInput.addEventListener("input", () => searchExec(searchInput.value));

// Safari emits `search` when the built-in clear button is used.
searchInput.addEventListener("search", () => searchExec(searchInput.value));

document.addEventListener("keydown", (event) => {
    if (!["ArrowDown", "ArrowUp", "Escape"].includes(event.key)) return;
    const links = [...searchResults.querySelectorAll("a")];
    const currentIndex = links.indexOf(document.activeElement);

    if (event.key === "Escape") {
        if (currentIndex === -1) return;
        event.preventDefault();
        searchInput.focus();
        return;
    }

    if (!links.length) return;
    event.preventDefault();

    if (currentIndex === -1) {
        focusResult(event.key === "ArrowDown" ? links[0] : links.at(-1));
        return;
    }

    const nextIndex = event.key === "ArrowDown"
        ? Math.min(currentIndex + 1, links.length - 1)
        : Math.max(currentIndex - 1, 0);
    focusResult(links[nextIndex]);
});

document.addEventListener("keydown", (event) => {
    const isResultFocused = searchResults.contains(document.activeElement);
    const isCharacter = event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey;
    const isDeletion = event.key === "Backspace" || event.key === "Delete";
    if (!isResultFocused || (!isCharacter && !isDeletion) || event.isComposing) return;

    event.preventDefault();
    searchInput.focus({ preventScroll: true });

    let start = searchInput.selectionStart ?? searchInput.value.length;
    let end = searchInput.selectionEnd ?? start;
    if (isDeletion && start === end) {
        if (event.key === "Backspace") start = Math.max(0, start - 1);
        if (event.key === "Delete") end = Math.min(searchInput.value.length, end + 1);
    }

    searchInput.setRangeText(isCharacter ? event.key : "", start, end, "end");
    searchInput.dispatchEvent(new Event("input", { bubbles: true }));
});

updateFilters();
searchInput.focus();
