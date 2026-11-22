const form=document.querySelector("#storage");
const minutes=document.querySelector("#storage-minutes");
const copies=document.querySelector("#storage-copies");
const channels=document.querySelector("#storage-mode");
const quality=document.querySelector("#storage-quality");
const result=document.querySelector("#storage-size");
const details=document.querySelector("#storage-description");
const format=new Intl.NumberFormat("en-IE",{maximumFractionDigits:2});

function update() {
  if (!minutes.validity.valid || !copies.validity.valid) {
    result.value="—";
    details.textContent="Enter whole minutes and between 1 and 20 copies.";
    return;
  }
  const [rate,bits]=quality.value.split(":").map(Number);
  const bytes=minutes.valueAsNumber*60*Number(channels.value)*rate*(bits/8)*copies.valueAsNumber;
  const gb=bytes>=1e9;
  result.value=format.format(bytes/(gb?1e9:1e6))+(gb?" GB":" MB");
  details.textContent=format.format(bytes)+" bytes of PCM audio. File headers and metadata are excluded.";
}
form.addEventListener("input",update);
form.addEventListener("submit",event=>event.preventDefault());
update();
