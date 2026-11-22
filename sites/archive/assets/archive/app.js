const audio = document.querySelector("#sample");
const versions = [...document.querySelectorAll("[data-audio]")];
const playerStatus = document.querySelector("#player-status");
let selected = "before";
let requestedPosition = 0;
let revision = 0;

audio.addEventListener("loadedmetadata", () => {
  if (audio.currentSrc.endsWith("/" + selected + ".mp3")) {
    audio.currentTime = Math.min(requestedPosition, audio.duration);
  }
});

for (const button of versions) {
  button.addEventListener("click", () => {
    const choice = button.dataset.audio;
    if (choice === selected) return;

    const resume = !audio.paused && !audio.ended;
    if (audio.readyState >= HTMLMediaElement.HAVE_METADATA) {
      requestedPosition = audio.currentTime;
    }

    selected = choice;
    const currentRevision = ++revision;
    for (const version of versions) {
      version.setAttribute("aria-pressed", String(version === button));
    }
    playerStatus.textContent = choice === "before" ? "Selected: before, raw transfer." : "Selected: after, restored.";
    audio.src = "/assets/archive/" + choice + ".mp3";

    if (resume) {
      audio.play().catch(error => {
        if (revision === currentRevision && error.name !== "AbortError") {
          playerStatus.textContent = "Press play to hear the selected version.";
        }
      });
    }
  });
}

const estimate = document.querySelector("#estimate");
const total = document.querySelector("#estimate-total");
const breakdown = document.querySelector("#breakdown");
const count = document.querySelector("#count");
const minutes = document.querySelector("#minutes");
const format = document.querySelector("#format");
const restoration = document.querySelector("#restore");
const currency = new Intl.NumberFormat("en-IE", {style:"currency", currency:"EUR"});
const cash = cents => currency.format(cents / 100);
const rates = {
  cassette:{item:600, minute:35},
  reel:{item:1200, minute:55},
  micro:{item:800, minute:45},
};

function calculateEstimate() {
  if (!count.validity.valid || !minutes.validity.valid) {
    total.value = "—";
    breakdown.textContent = "Enter 1–50 items and 1–240 whole minutes per item.";
    return;
  }
  const units = count.valueAsNumber;
  const duration = units * minutes.valueAsNumber;
  const rate = rates[format.value];
  const itemFee = units * rate.item;
  const transfer = duration * rate.minute;
  const cleanup = restoration.checked ? duration * 30 : 0;
  total.value = cash(itemFee + transfer + cleanup);
  breakdown.textContent = units + " × " + cash(rate.item) + " setup + " + duration + " min × " + cash(rate.minute) + " transfer" +
    (restoration.checked ? " + " + duration + " min × €0.30 restoration." : ".");
}

estimate.addEventListener("input", calculateEstimate);
estimate.addEventListener("submit", event => event.preventDefault());
calculateEstimate();
