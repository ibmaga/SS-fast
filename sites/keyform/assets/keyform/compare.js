const first = document.querySelector("#compare-a");
const second = document.querySelector("#compare-b");
const rows = document.querySelector("#compare-parts");
const status = document.querySelector("#compare-status");
const labels = {case:"Case",layout:"Layout",pcb:"PCB",plate:"Plate",switches:"Switches",stabs:"Stabilizers"};
const params = new URLSearchParams(location.search);
for (const select of [first,second]) {
  for (const preset of presets) select.add(new Option(preset.title,preset.id));
}
first.value = presets.some(p=>p.id===params.get("a")) ? params.get("a") : presets[0].id;
second.value = presets.some(p=>p.id===params.get("b")) ? params.get("b") :
  presets.find(p=>p.id!==first.value).id;

function renderComparison() {
  const a = presets.find(p=>p.id===first.value);
  const b = presets.find(p=>p.id===second.value);
  let changes = 0;
  document.querySelector("#compare-left").textContent=a.title;
  document.querySelector("#compare-right").textContent=b.title;
  document.querySelector("#configure-a").href="/build.html?"+new URLSearchParams(a.parts);
  document.querySelector("#configure-b").href="/build.html?"+new URLSearchParams(b.parts);
  rows.replaceChildren(...Object.keys(labels).map(key => {
    const row = document.createElement("tr");
    const title = document.createElement("th");
    title.scope="row";
    title.textContent=labels[key];
    const cells = [a,b].map(preset => {
      const cell = document.createElement("td");
      const part = parts[key].find(entry=>entry.id===preset.parts[key]);
      if (key === "layout") {
        cell.textContent=part.name;
      } else {
        const link = document.createElement("a");
        link.href="/catalog/"+key+"-"+part.id+".html";
        link.textContent=part.name;
        cell.append(link);
      }
      return cell;
    });
    if (a.parts[key]!==b.parts[key]) {
      changes++;
      row.classList.add("different");
    }
    row.append(title,...cells);
    return row;
  }));
  status.textContent=changes ? changes+(changes===1?" selection differs.":" selections differ.") : "Both builds have the same selections.";
  const url=new URL(location.href);
  url.search=new URLSearchParams({a:a.id,b:b.id});
  history.replaceState(null,"",url);
}
first.addEventListener("change",renderComparison);
second.addEventListener("change",renderComparison);
renderComparison();
