const search=document.querySelector("#catalog-search");
const category=document.querySelector("#catalog-category");
const resultCount=document.querySelector("#catalog-count");
const empty=document.querySelector("#catalog-empty");
const cards=[...document.querySelectorAll("[data-category]")];

function filterCatalog(){
  const query=search.value.trim().toLowerCase();
  let count=0;
  for(const card of cards){
    const matchesType=!category.value||card.dataset.category===category.value;
    card.hidden=!(matchesType&&card.textContent.toLowerCase().includes(query));
    if(!card.hidden) count++;
  }
  resultCount.textContent=count+" of "+cards.length;
  empty.hidden=count!==0;
}

search.addEventListener("input",filterCatalog);
category.addEventListener("change",filterCatalog);
filterCatalog();
