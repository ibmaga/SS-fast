const parts = {
  case:[
    {id:"k65", name:"Workshop 65 · tray mount", family:"K65"},
    {id:"k75", name:"Workshop 75 · gasket mount", family:"K75"},
    {id:"m65", name:"Magnetic 65 · top mount", family:"M65"},
  ],
  layout:[{id:"ANSI", name:"ANSI · wide left Shift"},{id:"ISO",name:"ISO · tall Enter"}],
  pcb:[
    {id:"k65a",name:"K65 ANSI · MX 5 pin",family:"K65",layout:"ANSI",socket:"MX",pins:5,stab:"pcb"},
    {id:"k65i",name:"K65 ISO · MX 3 pin",family:"K65",layout:"ISO",socket:"MX",pins:3,stab:"pcb"},
    {id:"k75a",name:"K75 ANSI · MX 5 pin",family:"K75",layout:"ANSI",socket:"MX",pins:5,stab:"pcb"},
    {id:"k75i",name:"K75 ISO · MX 5 pin",family:"K75",layout:"ISO",socket:"MX",pins:5,stab:"pcb"},
    {id:"m65a",name:"M65 ANSI · Hall effect",family:"M65",layout:"ANSI",socket:"HE",stab:"plate"},
  ],
  plate:[
    {id:"k65a",name:"K65 ANSI aluminum",family:"K65",layout:"ANSI",stab:"pcb"},
    {id:"k65i",name:"K65 ISO polycarbonate",family:"K65",layout:"ISO",stab:"pcb"},
    {id:"k75a",name:"K75 ANSI FR4",family:"K75",layout:"ANSI",stab:"pcb"},
    {id:"k75i",name:"K75 ISO aluminum",family:"K75",layout:"ISO",stab:"pcb"},
    {id:"m65a",name:"M65 ANSI steel",family:"M65",layout:"ANSI",stab:"plate"},
  ],
  switches:[
    {id:"line",name:"Line · MX linear, 5 pin",socket:"MX",pins:5},
    {id:"step",name:"Step · MX tactile, 3 pin",socket:"MX",pins:3},
    {id:"quiet",name:"Quiet · MX silent, 5 pin",socket:"MX",pins:5},
    {id:"pulse",name:"Pulse · M65 magnetic linear",socket:"HE"},
  ],
  stabs:[
    {id:"pcb",name:"PCB screw in",mount:"pcb"},
    {id:"plate",name:"Plate clip in",mount:"plate"},
  ],
};
const form = document.querySelector("#build-form");
const title = document.querySelector("#fit-title");
const status = document.querySelector("#fit-status");
const list = document.querySelector("#fit-list");
const exportButton = document.querySelector("#export");
const controls = Object.fromEntries(Object.keys(parts).map(key => [key,document.getElementById(key)]));
for (const [key, entries] of Object.entries(parts)) {
  for (const entry of entries) controls[key].add(new Option(entry.name, entry.id));
}

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
  const checks = fitChecks(selections());
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
