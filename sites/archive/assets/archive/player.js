const audio = document.querySelector("#sample");
const versions = [...document.querySelectorAll("[data-audio]")];
const playerStatus = document.querySelector("#player-status");
const sourceBase = audio.dataset.base || "/assets/archive/";
const sampleUrl = version => new URL(sourceBase + version + ".mp3",document.baseURI).href;
let selected = "before";
let requestedPosition = 0;
let revision = 0;

audio.addEventListener("loadedmetadata", () => {
  if (audio.currentSrc === sampleUrl(selected)) {
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
    audio.src = sampleUrl(choice);

    if (resume) {
      audio.play().catch(error => {
        if (revision === currentRevision && error.name !== "AbortError") {
          playerStatus.textContent = "Press play to hear the selected version.";
        }
      });
    }
  });
}
