//! Metadata-only, offline bridge to the pinned, unmodified Tokscale parsers.
use serde::Serialize;
use std::{collections::{BTreeMap,HashSet,hash_map::DefaultHasher},hash::{Hash,Hasher},io::{self,Write},path::PathBuf};
use tokscale_core::{ClientId,LocalParseOptions,clients::PathRoot,scanner::{self,ScannerSettings},sessions::UnifiedMessage};
const PIN:&str="82613d2f5e96654ce3729892afbb0025979f1c75";
#[derive(Serialize)]
#[serde(rename_all="camelCase")]
struct Event {id:String,provider:String,timestamp_ms:i64,model:String,input:u64,output:u64,cache_read:u64,cache_write:u64,reasoning:u64,unclassified:u64}
#[derive(Serialize)]
struct Source {provider:String,state:&'static str,records:usize}
#[derive(Serialize)]
struct Report {version:u8,engine:&'static str,commit:&'static str,sources:Vec<Source>,events:Vec<Event>}
fn convert(row:UnifiedMessage,ordinal:usize)->Option<Event> {
 if ClientId::from_str(row.client.as_str()).is_none(){return None;}
 let t=row.tokens;
 if [t.input,t.output,t.cache_read,t.cache_write,t.reasoning].iter().any(|v|*v<0 || *v>1_000_000_000_000){return None;}
 let mut hash=DefaultHasher::new();
 // Upstream has already deduplicated forks and mirrored records. Preserve
 // distinct id-less requests that happen to have the same timestamp/counts.
 (&row.client,&row.session_id,row.timestamp,&row.model_id,&row.dedup_key,ordinal).hash(&mut hash);
 Some(Event{id:format!("{}:{:016x}",row.client,hash.finish()),provider:row.client.to_string(),timestamp_ms:row.timestamp,model:row.model_id.to_string(),input:(t.input+t.cache_read+t.cache_write) as u64,output:(t.output+t.reasoning) as u64,cache_read:t.cache_read as u64,cache_write:t.cache_write as u64,reasoning:t.reasoning as u64,unclassified:0})
}
fn catalog()->serde_json::Value {
 let home="/SHOWMAC_HOME";
 let enabled=ClientId::iter().collect::<HashSet<_>>();
 let extras=scanner::built_in_extra_scan_paths_for(home,&enabled,false);
 serde_json::json!(ClientId::iter().map(|id|{
  let def=id.data();let mut paths=vec![def.resolve_path_with_env_strategy(home,false)];
  paths.extend(extras.iter().filter(|(client,_)|*client==id).map(|(_,p)|p.to_string_lossy().into_owned()));
  paths.sort();paths.dedup();
  let env=match def.root {PathRoot::EnvVar{var,..}=>Some(var),_=>None};
  serde_json::json!({"id":id.as_str(),"title":id.display_name(),"paths":paths.into_iter().map(|p|p.replace(home,"~")).collect::<Vec<_>>(),"environment":env,"relative":def.relative_path,"custom":!matches!(id,ClientId::Kilo|ClientId::Crush|ClientId::Goose),"cached":id==ClientId::Cursor})
 }).collect::<Vec<_>>())
}
fn scan()->Result<Report,String> {
 // This switch is monotonic. Even an upstream parser's optional network path
 // cannot fetch pricing, sync usage, or send telemetry in this process.
 tokscale_core::network::go_offline();
 let paths:BTreeMap<String,Vec<PathBuf>>=std::env::var("SHOWMAC_AGENT_PATHS").ok().and_then(|s|serde_json::from_str(&s).ok()).unwrap_or_default();
 let settings=ScannerSettings{extra_scan_paths:paths,..Default::default()};
 let options=LocalParseOptions{home_dir:std::env::var("HOME").ok(),use_env_roots:true,clients:Some(ClientId::iter().map(|id|id.as_str().to_owned()).collect()),scanner_settings:settings,..Default::default()};
 let runtime=tokio::runtime::Builder::new_current_thread().build().map_err(|e|e.to_string())?;
 let rows=runtime.block_on(tokscale_core::parse_local_unified_messages_with_pricing_uncached(options,None))?;
 let mut events=rows.into_iter().enumerate().filter_map(|(n,row)|convert(row,n)).filter(|e|e.input+e.output+e.unclassified>0).collect::<Vec<_>>();
 events.sort_by_key(|event|event.timestamp_ms);
 let sources=ClientId::iter().map(|id|{let records=events.iter().filter(|e|e.provider==id.as_str()).count();Source{provider:id.as_str().into(),state:if records>0{"ready"}else{"empty"},records}}).collect();
 Ok(Report{version:1,engine:"tokscale",commit:PIN,sources,events})
}
fn main(){
 if std::env::args().any(|a|a=="--catalog"){println!("{}",catalog());return;}
 if std::env::args().any(|a|a=="--capabilities"){println!("{}",serde_json::json!({"version":1,"engine":"tokscale","commit":PIN,"providers":ClientId::iter().map(|c|c.as_str()).collect::<Vec<_>>()}));return;}
 let report=scan().unwrap_or_else(|_|std::process::exit(1));let stdout=io::stdout();let mut output=io::BufWriter::new(stdout.lock());serde_json::to_writer(&mut output,&report).expect("write usage metadata");output.write_all(b"\n").ok();
}
#[cfg(test)]
mod tests {
 use super::*;
 #[test]fn catalog_matches_every_upstream_source(){let rows=catalog();assert_eq!(rows.as_array().unwrap().len(),60);assert_eq!(ClientId::COUNT,60);assert!(rows.as_array().unwrap().iter().any(|r|r["id"]=="cursor"&&r["cached"]==true));}
 #[test]fn counter_conversion_does_not_repeat_cache_or_reasoning(){
  let row:UnifiedMessage=serde_json::from_value(serde_json::json!({"client":"cursor","model_id":"example","provider_id":"test","session_id":"PRIVATE_SESSION","timestamp":1793923200000_i64,"date":"2026-11-06","tokens":{"input":10,"output":5,"cache_read":30,"cache_write":20,"cache_write_1h":0,"reasoning":2},"cost":1,"agent":null,"dedup_key":null})).unwrap();
  let event=convert(row,0).unwrap();assert_eq!(event.input,60);assert_eq!(event.output,7);let text=serde_json::to_string(&event).unwrap();assert!(!text.contains("PRIVATE"));assert!(!text.contains("cost"));
 }
}
