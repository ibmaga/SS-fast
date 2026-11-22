const form = document.querySelector("#estimate");
const list = document.querySelector("#quote-lines");
const base = list.querySelector("[data-line]");
const prototype = base.cloneNode(true);
const total = document.querySelector("#estimate-total");
const breakdown = document.querySelector("#breakdown");
const add = document.querySelector("#quote-add");
const download = document.querySelector("#quote-download");
const settings = new URLSearchParams(location.search);
const labels = {"cassette":"Compact cassette","reel":"Open reel","micro":"Microcassette"};
const rates = {
  cassette:{item:600, minute:35},
  reel:{item:1200, minute:55},
  micro:{item:800, minute:45},
};
const currency = new Intl.NumberFormat("en-IE",{style:"currency",currency:"EUR"});
const cash = value => currency.format(value / 100);
let next = 2;

function fields(row) {
  return Object.fromEntries([...row.querySelectorAll("[data-field]")].map(input => [input.dataset.field,input]));
}

function linePrice(row) {
  const {format,count,minutes,restore} = fields(row);
  if (!count.validity.valid || !minutes.validity.valid) return null;
  const copies = count.valueAsNumber;
  const length = minutes.valueAsNumber;
  const rate = rates[format.value];
  const cents = copies * (rate.item + length * (rate.minute + (restore.checked ? 30 : 0)));
  return {cents, label:labels[format.value] + " · " + copies + " × " + length + " min · " +
    (restore.checked ? "with restoration" : "transfer only")};
}

function calculate() {
  const rows = [...list.querySelectorAll("[data-line]")];
  const entries = rows.map(linePrice);
  add.disabled = rows.length >= 12;
  breakdown.replaceChildren(...entries.map((entry,i) => {
    const item = document.createElement("li");
    item.textContent = entry ? entry.label + " · " + cash(entry.cents) :
      "Line " + (i+1) + " needs 1–50 items and 1–240 whole minutes per item.";
    return item;
  }));
  download.disabled = entries.some(entry => entry === null);
  total.value = download.disabled ? "—" : cash(entries.reduce((sum,entry) => sum+entry.cents,0));
}

const seed = fields(base);
if (Object.hasOwn(rates,settings.get("format"))) seed.format.value = settings.get("format");
const seededMinutes = Number(settings.get("minutes"));
if (Number.isInteger(seededMinutes) && seededMinutes >= 1 && seededMinutes <= 240) seed.minutes.value = seededMinutes;
seed.restore.checked = settings.get("restore") === "1";

add.addEventListener("click", () => {
  const row = prototype.cloneNode(true);
  const sequence = next++;
  for (const input of row.querySelectorAll("[data-field]")) {
    const label = row.querySelector('label[for="' + input.id + '"]');
    input.id += "-" + sequence;
    if (label) label.htmlFor = input.id;
  }
  const remove = document.createElement("button");
  remove.className = "button secondary";
  remove.type = "button";
  remove.textContent = "Remove line";
  remove.addEventListener("click", () => {
    row.remove();
    calculate();
    (add.disabled ? download : add).focus();
  });
  row.append(remove);
  list.append(row);
  calculate();
  fields(row).format.focus();
});

download.addEventListener("click", () => {
  const lines = [...list.querySelectorAll("[data-line]")].map(linePrice);
  if (lines.some(line => line === null)) return;
  const text = ["Signal Archive · Estimate","",...lines.map(line => line.label+" · "+cash(line.cents)),"","Total: "+total.value].join("\n");
  const url = URL.createObjectURL(new Blob([text],{type:"text/plain"}));
  const link = document.createElement("a");
  link.href = url;
  link.download = "signal-archive-estimate.txt";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url),1000);
});
form.addEventListener("input",calculate);
form.addEventListener("submit",event=>event.preventDefault());
calculate();
