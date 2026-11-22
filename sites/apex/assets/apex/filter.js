const controls = document.querySelector("[data-filter]");
const buttons = [...controls.querySelectorAll("button")];
const entries = [...document.querySelectorAll("[data-category]")];
const count = document.querySelector("[data-count]");

function selectCategory(selected) {
  for (const button of buttons) {
    button.setAttribute("aria-pressed", String(button === selected));
  }

  const category = selected.dataset.value;
  let visible = 0;
  for (const entry of entries) {
    entry.hidden = category !== "All" && entry.dataset.category !== category;
    if (!entry.hidden) visible += 1;
  }
  count.textContent = `Showing ${visible} of ${entries.length}`;
}

for (const button of buttons) {
  button.addEventListener("click", () => selectCategory(button));
}
selectCategory(buttons[0]);
controls.hidden = false;
