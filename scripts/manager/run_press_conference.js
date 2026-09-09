#!/usr/bin/env node
// Experimental press-conference controller.
// State/choices/button geometry come from fm.exe memory; actions use SendInput.
// Until question text is decoded, model answering requires --allow-choice-only.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { OllamaProvider } = require('./provider');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const STATE = path.join(__dirname, 'read_press_state.js');
const CHOICES = path.join(__dirname, 'read_press_choices.js');
const BUTTONS = path.join(__dirname, 'read_ui_buttons.js');
const CLICK = path.join(REPO, 'scripts', 'win', 'click.ps1');
const FOCUS = path.join(REPO, 'scripts', 'win', 'focus.ps1');
const PROFILE = path.join(__dirname, 'profiles', 'pragmatic.json');
const LOG = path.join(REPO, 'data', 'logs', 'decisions.jsonl');
const ALLOW_CHOICE_ONLY = process.argv.includes('--allow-choice-only');

function run(cmd,args) { return execFileSync(cmd,args,{encoding:'utf8',maxBuffer:64*1024*1024}); }
function node(script,args=[]) { return run(process.execPath,[script,...args]); }
function ps(script,args=[]) { return run(PS,['-NoProfile','-ExecutionPolicy','Bypass','-File',script,...args]); }
function parseJson(text) {
  const line=text.trim().split(/\r?\n/).filter(x=>x.trim().startsWith('{')).pop();
  if(!line) throw new Error('no JSON object in child output');
  return JSON.parse(line.replace(/^\uFEFF/,''));
}
function sleep(ms) { run(PS,['-NoProfile','-Command',`Start-Sleep -Milliseconds ${ms}`]); }
function appendLog(row) {
  fs.mkdirSync(path.dirname(LOG),{recursive:true});
  fs.appendFileSync(LOG,JSON.stringify({timestamp:new Date().toISOString(),...row})+'\n');
}
function clickPoint(p) {
  ps(FOCUS,['-ProcessName','fm']);
  ps(CLICK,['-X',String(p.x),'-Y',String(p.y)]);
}
function pressState() { return parseJson(node(STATE,['--json'])); }
function uiButtons() { return parseJson(node(BUTTONS,['--json'])); }
function exactButton(buttons,text) {
  const hits=buttons.buttons.filter(b=>b.text===text);
  if(hits.length>1) throw new Error(`multiple visible buttons labelled '${text}'`);
  return hits[0] || null;
}

async function answerQuestion(provider,profile,state) {
  if(!state.current_question) throw new Error('answerQuestion called without current question');
  if(!ALLOW_CHOICE_ONLY) {
    throw new Error('current question text is not decoded; refusing choice-only model decision (use --allow-choice-only only for RE experiments)');
  }
  const choices=parseJson(node(CHOICES,['--json']));
  if(!choices.count) throw new Error('semantic state says question is active but no response choices were found');
  const optionText=choices.choices.map((c,i)=>`${i}: ${c.text}`).join('\n');
  const systemPrompt=`You are managing Aston Villa in Football Manager 2021. Manager profile: ${profile.name}; `+
    `risk tolerance ${profile.risk_tolerance}; tactical philosophy ${profile.tactical_philosophy}. `+
    `Choose the press response yourself.`;
  const initialContext=`Live pre-match press conference. FM question object ${state.current_question.id}. `+
    `Question text is not yet decoded; this RE-only run must choose from the five answer texts.\n${optionText}\n`+
    `Reply JSON only: {"index":0,"reasoning":"brief reason"}`;
  const result=await provider.decide({eventType:'press_conference_answer',systemPrompt,initialContext,strategy:'oneshot'});
  const idx=Number(result.decision?.index);
  if(!Number.isInteger(idx)||idx<0||idx>=choices.count) throw new Error(`invalid model choice ${idx}`);
  const chosen=choices.choices[idx];
  console.log(`[${state.answered_count+1}] ${chosen.text}`);
  console.log(`    ${result.decision?.reasoning||''}`);
  clickPoint(chosen.click);
  sleep(900);
  const after=pressState();
  const verified=after.answered_count>state.answered_count ||
    after.current_question?.address!==state.current_question.address;
  appendLog({eventType:'press_conference_answer',model:result.model,strategy:result.strategy,
    state,choices:choices.choices.map(c=>c.text),decision:result.decision,tokens:result.tokens,
    wallClockMs:result.wallClockMs,applied:true,verified,click:chosen.click,after_state:after,
    caveat:'question text unavailable; choice-only RE run'});
  if(!verified) throw new Error('press answer click did not advance semantic press state');
}

function handleTerminalState() {
  const buttons=uiButtons();
  const continueSummary=exactButton(buttons,'Continue To Summary');
  const leave=exactButton(buttons,'Leave Press Conference');
  if(continueSummary) {
    console.log('[terminal] Continue To Summary');
    clickPoint(continueSummary.click); sleep(900);
    appendLog({eventType:'press_conference_terminal',action:'continue_to_summary',applied:true,
      verified:null,click:continueSummary.click});
    return 'continue';
  }
  if(leave) {
    console.log('[terminal] Leave Press Conference');
    clickPoint(leave.click); sleep(900);
    const afterButtons=uiButtons();
    const stillThere=exactButton(afterButtons,'Leave Press Conference');
    const verified=!stillThere;
    appendLog({eventType:'press_conference_terminal',action:'leave_press_conference',applied:true,
      verified,click:leave.click});
    if(!verified) throw new Error('Leave Press Conference did not disappear after click');
    console.log('press conference: exited and verified');
    return 'done';
  }
  console.log('press conference: no current question and no terminal press controls; already exited/inactive');
  return 'done';
}

async function main() {
  const profile=JSON.parse(fs.readFileSync(PROFILE,'utf8'));
  let provider=null;
  ps(FOCUS,['-ProcessName','fm']);
  for(let turn=0;turn<32;turn++) {
    const state=pressState();
    // Critical safety gate: stale response widgets can survive after the final
    // question. Never even read/click them unless semantic state has a current question.
    if(state.current_question) {
      if(!provider) { provider=new OllamaProvider({model:'qwen3:8b'}); await provider.health(); await provider.warm(); }
      await answerQuestion(provider,profile,state);
    }
    else if(handleTerminalState()==='done') return;
  }
  throw new Error('press conference exceeded 32 controller turns');
}
main().catch(e=>{console.error(`run_press_conference: ${e.message}`);process.exit(1);});
