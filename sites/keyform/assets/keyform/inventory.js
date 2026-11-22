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
const presets = [
  {
    "id": "everyday",
    "title": "Everyday 65",
    "use": "An ANSI tray mount reference build with a broad choice of MX switches.",
    "parts": {
      "case": "k65",
      "layout": "ANSI",
      "pcb": "k65a",
      "plate": "k65a",
      "switches": "line",
      "stabs": "pcb"
    }
  },
  {
    "id": "iso-compact",
    "title": "Compact ISO",
    "use": "A smaller ISO build pairing the three-pin socket with a matching tactile switch.",
    "parts": {
      "case": "k65",
      "layout": "ISO",
      "pcb": "k65i",
      "plate": "k65i",
      "switches": "step",
      "stabs": "pcb"
    }
  },
  {
    "id": "quiet-desk",
    "title": "Quiet desk 75",
    "use": "A gasket mount board with a dedicated function row and silent MX switches.",
    "parts": {
      "case": "k75",
      "layout": "ANSI",
      "pcb": "k75a",
      "plate": "k75a",
      "switches": "quiet",
      "stabs": "pcb"
    }
  },
  {
    "id": "iso-studio",
    "title": "Studio ISO 75",
    "use": "The larger ISO layout, aluminum plate and five-pin linear switches.",
    "parts": {
      "case": "k75",
      "layout": "ISO",
      "pcb": "k75i",
      "plate": "k75i",
      "switches": "line",
      "stabs": "pcb"
    }
  },
  {
    "id": "magnetic",
    "title": "Magnetic 65",
    "use": "An ANSI Hall-effect build with a dedicated PCB, steel plate and magnetic switches.",
    "parts": {
      "case": "m65",
      "layout": "ANSI",
      "pcb": "m65a",
      "plate": "m65a",
      "switches": "pulse",
      "stabs": "plate"
    }
  }
];
