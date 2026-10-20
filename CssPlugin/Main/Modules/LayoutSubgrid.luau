local S={VERSION=1}
function S.is(style,axis)
 local ast=style._gridTracks and style._gridTracks[axis]
 return style.display=='grid'and ast and ast[1]and ast[1].kind=='subgrid'
end
function S.slice(tracks,names,first,span,minimum,gap)
 local out={sizes={},names={},gap=gap or 0};local begin=minimum+first-1
 for i=1,span do out.sizes[i]=tracks and tracks.sizes[first+i-1]or 0 end
 if tracks and span>1 then out.gap=tracks.starts[first+1]-tracks.ends[first]end
 for name,lines in pairs(names or{})do
  local selected={};for _,line in ipairs(lines)do if line>=begin and line<=begin+span then selected[#selected+1]=line-begin+1 end end
  if #selected>0 then out.names[name]=selected end
 end
 return out
end
function S.binding(item,styles,cols,rows,colNames,rowNames,minCol,minRow,gx,gy)
 local style=styles[item.node.key];local out={}
 if S.is(style,'columns')then out.columns=S.slice(cols,colNames,item.col,item.colSpan,minCol,gx)end
 if S.is(style,'rows')then out.rows=S.slice(rows,rowNames,item.row,item.rowSpan,minRow,gy)end
 return next(out)and out or nil
end
function S.signature(binding)
 local out={}
 for _,axis in ipairs({'columns','rows'})do local part=binding and binding[axis]
  if part then out[#out+1]=axis..':'..part.gap..':'..table.concat(part.sizes,',');local keys={};for name in pairs(part.names)do keys[#keys+1]=name end;table.sort(keys);for _,name in ipairs(keys)do out[#out+1]=name..':'..table.concat(part.names[name],',')end end
 end
 return table.concat(out,'|')
end
function S.definitions(ast,binding,gap,explicit,before,after)
 if not binding then return nil end
 local count=#binding.sizes;local names={};for name,lines in pairs(binding.names)do names[name]=table.clone(lines)end
 for line,list in ipairs(ast[1].names or{})do if line<=count+1 then for _,name in ipairs(list)do names[name]=names[name]or{};if not table.find(names[name],line)then names[name][#names[name]+1]=line;table.sort(names[name])end end end end
 gap=explicit and gap or binding.gap
 local difference=(gap-binding.gap)/2;local defs={}
 for i,size in ipairs(binding.sizes)do
  local breadth=math.max(0,size-(i==1 and before or difference)-(i==count and after or difference))
  defs[i]={kind='track',min=breadth,max=breadth,length=breadth}
 end
 return defs,names,gap
end
function S.contribute(output,contributions,first,span,before,after)
 for _,part in ipairs(contributions or{})do
  local a=math.clamp(part.first,1,span);local b=math.clamp(part.last,a,span)
  local extra=(a==1 and before or 0)+(b==span and after or 0)
  output[#output+1]={first=first+a-1,last=first+b-1,min=part.min+extra,max=part.max+extra}
 end
end
return S
