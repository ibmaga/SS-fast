const form = document.querySelector("#build-form");
const title = document.querySelector("#fit-title");
const status = document.querySelector("#fit-status");
const list = document.querySelector("#fit-list");
const exportButton = document.querySelector("#export");
const controls = Object.fromEntries(Object.keys(parts).map(key => [key,document.getElementById(key)]));
for (const [key, entries] of Object.entries(parts)) {
  for (const entry of entries) controls[key].add(new Option(entry.name, entry.id));
}

const buildLink = document.querySelector("#build-link");
const copyMessage = document.querySelector("#copy-message");
const incoming = new URLSearchParams(location.search);
for (const [key,control] of Object.entries(controls)) {
  const value = incoming.get(key);
  if (parts[key].some(part => part.id === value)) control.value = value;
}

document.querySelector("#copy-build").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(buildLink.value);
    copyMessage.textContent = "Build link copied.";
  } catch {
    buildLink.focus();
    buildLink.select();
    copyMessage.textContent = "Build link selected. Copy it to share.";
  }
});

function selections() {
  return Object.fromEntries(Object.entries(controls).map(([key,control]) =>
    [key,parts[key].find(part => part.id === control.value)]));
}

function supportsSwitch(pcb, choice) {
  return pcb.socket === choice.socket && (pcb.socket !== "MX" || choice.pins <= pcb.pins);
}

function fitChecks(chosen) {
  const {case: enclosure, layout, pcb, plate, switches, stabs} = chosen;
  return [
    [pcb.family === enclosure.family, "Case and PCB match.", "The PCB must match the " + enclosure.family + " case family."],
    [plate.family === enclosure.family && plate.family === pcb.family, "Plate matches case and PCB.", "The plate must match both the case and PCB family."],
    [pcb.layout === layout.id && plate.layout === layout.id, "Plate and PCB support " + layout.id + ".", "Both the PCB and plate must support " + layout.id + "."],
    [supportsSwitch(pcb,switches), "Switches fit the PCB sockets.", pcb.socket !== switches.socket ?
      "These switches use a different technology from the selected PCB." :
      "The selected MX switches have more pins than this PCB accepts."],
    [stabs.mount === pcb.stab && stabs.mount === plate.stab, "Stabilizer mounting matches.", "The stabilizers must fit the mounting specified by both PCB and plate."],
  ];
}

function render() {
  const chosen = selections();
  const url = new URL("/build.html",location.origin);
  url.search = new URLSearchParams(Object.entries(chosen).map(([key,part]) => [key,part.id]));
  buildLink.value = url.href;
  copyMessage.textContent = "";
  const checks = fitChecks(chosen);
  const failures = checks.filter(([ok]) => !ok).length;
  title.textContent = failures ? "Adjust your selection" : "Compatible build";
  status.textContent = failures ? failures + (failures === 1 ? " issue to resolve." : " issues to resolve.") : "All five fit checks passed.";
  list.replaceChildren(...checks.map(([ok, pass, fail]) => {
    const item = document.createElement("li");
    item.className = ok ? "pass" : "fail";
    item.textContent = (ok ? "Pass · " + pass : "Fix · " + fail);
    return item;
  }));
  exportButton.disabled = failures > 0;
}

form.addEventListener("change", render);
form.addEventListener("submit", event => event.preventDefault());

document.querySelector("#fit").addEventListener("click", () => {
  const chosen = selections();
  const boards = parts.pcb.filter(part => part.family === chosen.case.family);
  const board = boards.find(part => part.layout === chosen.layout.id) || boards[0];
  controls.layout.value = board.layout;
  controls.pcb.value = board.id;
  controls.plate.value = parts.plate.find(part => part.family === board.family && part.layout === board.layout).id;
  if (!supportsSwitch(board, chosen.switches)) {
    controls.switches.value = parts.switches.find(part => supportsSwitch(board,part)).id;
  }
  controls.stabs.value = parts.stabs.find(part => part.mount === board.stab).id;
  render();
});

exportButton.addEventListener("click", () => {
  const chosen = selections();
  if (fitChecks(chosen).some(([ok]) => !ok)) return;
  const labels = {case:"Case",layout:"Layout",pcb:"PCB",plate:"Plate",switches:"Switches",stabs:"Stabilizers"};
  const lines = Object.entries(chosen).map(([key,part]) => labels[key] + ": " + part.name);
  const url = URL.createObjectURL(new Blob(["Keyform Workshop\n\n", lines.join("\n"), "\n"], {type:"text/plain"}));
  const link = document.createElement("a");
  link.href = url;
  link.download = "keyform-build.txt";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
render();
