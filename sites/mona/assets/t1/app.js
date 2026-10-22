(function(){
  var b=document.querySelector('.burger'),l=document.querySelector('.links');
  if(b&&l)b.addEventListener('click',function(){l.classList.toggle('open')});
  var y=document.getElementById('yr');if(y)y.textContent=new Date().getFullYear();
  var drop=document.getElementById('drop'),inp=document.getElementById('file'),list=document.getElementById('picked'),note=document.getElementById('note');
  if(drop&&inp){
    var size=function(n){return n<1048576?(n/1024).toFixed(0)+' KB':(n/1048576).toFixed(1)+' MB'};
    var show=function(files){
      list.innerHTML='';
      Array.prototype.slice.call(files,0,8).forEach(function(f){
        var li=document.createElement('li'),a=document.createElement('span'),s=document.createElement('span');
        a.textContent=f.name;s.textContent=size(f.size);li.appendChild(a);li.appendChild(s);list.appendChild(li);
      });
      note.textContent=files.length?'Sign in to create your private link.':'';
    };
    ['dragenter','dragover'].forEach(function(e){drop.addEventListener(e,function(ev){ev.preventDefault();drop.classList.add('over')})});
    ['dragleave','drop'].forEach(function(e){drop.addEventListener(e,function(ev){ev.preventDefault();drop.classList.remove('over')})});
    drop.addEventListener('drop',function(ev){show(ev.dataTransfer.files)});
    inp.addEventListener('change',function(){show(inp.files)});
  }
  var f=document.getElementById('login');
  if(f)f.addEventListener('submit',function(ev){ev.preventDefault();document.getElementById('msg').textContent='Incorrect email or password.'});
})();
