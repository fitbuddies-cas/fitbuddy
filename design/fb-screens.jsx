// FitBuddy screens — one component per discrete screen state.
// Designed for 402×874 iPhone frame.

// ─────────────────────────────────────────────────────────────────────
// US-1 · API-Key sicher speichern
// ─────────────────────────────────────────────────────────────────────

function FBWelcomeScreen({ onStart }) {
  return (
    <FBScreen padding="0">
      <div style={{ paddingTop: 64, padding: '64px 24px 24px' }}>
        {/* Wordmark */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 88 }}>
          <div style={{
            width: 32, height: 32, borderRadius: 9,
            background: FB.ink, color: '#fff',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 17, fontWeight: 700, letterSpacing: -0.4,
          }}>fb</div>
          <span style={{ fontSize: 17, fontWeight: 600, letterSpacing: -0.3 }}>FitBuddy</span>
        </div>

        {/* Headline */}
        <div style={{ fontSize: 38, fontWeight: 700, lineHeight: 1.05, letterSpacing: -1.2, textWrap: 'balance' }}>
          Your training,<br/>
          <span style={{ color: FB.muted }}>one picture.</span>
        </div>
        <div style={{ marginTop: 20, fontSize: 17, lineHeight: 1.45, color: FB.ink2, maxWidth: 320 }}>
          Pull 90 days from Hevy, see your load at a glance, and get an AI progression
          recommendation when you want one.
        </div>

        {/* Trust bullets */}
        <div style={{ marginTop: 56, display: 'flex', flexDirection: 'column', gap: 18 }}>
          {[
            ['On-device only', 'API keys stay in the iOS Keychain. Nothing leaves your phone except your own API calls.'],
            ['On-demand AI', 'Analysis runs only when you tap Analyze. No background pings.'],
          ].map(([t, d]) => (
            <div key={t} style={{ display: 'flex', gap: 12 }}>
              <div style={{ width: 6, height: 6, borderRadius: 3, background: FB.accent, marginTop: 8, flexShrink: 0 }} />
              <div>
                <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2 }}>{t}</div>
                <div style={{ fontSize: 14, color: FB.muted, marginTop: 2, lineHeight: 1.4 }}>{d}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Bottom CTA */}
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 48 }}>
        <FBButton kind="primary" onClick={onStart}>Get started</FBButton>
        <div style={{ textAlign: 'center', marginTop: 12, fontSize: 12, color: FB.muted }}>
          By continuing you accept the{' '}
          <span style={{ color: FB.ink2, textDecoration: 'underline' }}>data &amp; AI consent</span>.
        </div>
      </div>
    </FBScreen>
  );
}

function FBKeyEntryScreen({ stage = 'empty', onVerify, onRetry }) {
  // stage: 'empty' | 'typed' | 'validating' | 'invalid'
  const hasInput = stage !== 'empty';
  const validating = stage === 'validating';
  const invalid = stage === 'invalid';

  const maskedKey = 'hv_live_••••••••••••••••3f7a';
  const typed = 'hv_live_8b3c91f2e4d6a7b8c9d0e1f23f7a';

  return (
    <FBScreen padding="0" bg={FB.bg}>
      <div style={{ padding: '54px 20px 0' }}>
        {/* Step indicator */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 22 }}>
          {[0,1,2].map(i => (
            <div key={i} style={{
              flex: 1, height: 3, borderRadius: 2,
              background: i === 0 ? FB.ink : FB.border,
            }} />
          ))}
          <div style={{ fontSize: 12, color: FB.muted, marginLeft: 8, fontWeight: 500 }}>Step 1 of 3</div>
        </div>

        <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.6, lineHeight: 1.1 }}>
          Connect Hevy
        </div>
        <div style={{ marginTop: 8, fontSize: 15, color: FB.ink2, lineHeight: 1.45 }}>
          Paste the API key from your Hevy account. We'll verify it before saving.
        </div>

        {/* Where to find */}
        <div style={{
          marginTop: 18, padding: 14, borderRadius: 14, background: FB.cardSubtle,
          display: 'flex', gap: 12, alignItems: 'flex-start',
          boxShadow: `0 0 0 1px ${FB.border}`,
        }}>
          <div style={{
            width: 56, height: 56, borderRadius: 10, flexShrink: 0,
            background: `repeating-linear-gradient(135deg, ${FB.border} 0 6px, transparent 6px 12px), ${FB.card}`,
            border: `1px dashed ${FB.ter}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 9, fontFamily: FB.fontMono, color: FB.muted, textAlign: 'center', lineHeight: 1.2,
          }}>hevy<br/>screen</div>
          <div style={{ fontSize: 13, color: FB.ink2, lineHeight: 1.4 }}>
            In Hevy, open <strong>Settings → Developer → API Keys</strong> and
            tap <strong>Create new key</strong>.
            <div style={{ marginTop: 6, color: FB.accent, fontWeight: 600 }}>
              Open Hevy ↗
            </div>
          </div>
        </div>

        {/* Input */}
        <div style={{ marginTop: 22 }}>
          <FBLabel>Hevy API key</FBLabel>
          <div style={{
            marginTop: 8, height: 56, borderRadius: 14, background: FB.card,
            boxShadow: invalid
              ? `0 0 0 2px ${FB.red}`
              : hasInput ? `0 0 0 1.5px ${FB.ink}` : `0 0 0 1px ${FB.border}`,
            display: 'flex', alignItems: 'center', padding: '0 14px', gap: 8,
            transition: 'box-shadow 120ms ease',
          }}>
            <FBLockIcon size={16} color={hasInput ? FB.ink2 : FB.muted} />
            <div style={{
              flex: 1, fontFamily: FB.fontMono, fontSize: 14, letterSpacing: -0.1,
              color: hasInput ? FB.ink : FB.muted, overflow: 'hidden', whiteSpace: 'nowrap',
            }}>
              {hasInput ? typed : 'hv_live_…'}
              {hasInput && !validating && <span className="fb-cursor" />}
            </div>
            {validating && <FBSpinner size={18} color={FB.muted} />}
          </div>

          {/* Storage note */}
          <div style={{
            marginTop: 10, display: 'flex', alignItems: 'center', gap: 6,
            fontSize: 12, color: FB.muted, paddingLeft: 2,
          }}>
            <FBLockIcon size={11} />
            Stored in Apple Keychain · this device only
          </div>
        </div>

        {/* Invalid banner */}
        {invalid && (
          <div className="fb-fade" style={{
            marginTop: 18, padding: 14, borderRadius: 14,
            background: FB.redSoft, boxShadow: `inset 0 0 0 1px ${FB.red}30`,
          }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: FB.red, letterSpacing: -0.2 }}>
              Hevy rejected this key (HTTP 401)
            </div>
            <div style={{ marginTop: 4, fontSize: 13, color: FB.ink2, lineHeight: 1.4 }}>
              The key may be revoked or mistyped. Open Hevy and generate a new one,
              then paste it here.
            </div>
            <div style={{ marginTop: 10, fontSize: 13, fontWeight: 600, color: FB.red }}>
              Open Hevy API settings ↗
            </div>
          </div>
        )}
      </div>

      {/* Bottom CTA */}
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 48 }}>
        <FBButton
          kind={invalid ? 'danger' : 'primary'}
          disabled={!hasInput || validating}
          onClick={invalid ? onRetry : onVerify}
        >
          {validating ? 'Verifying with Hevy…' : invalid ? 'Try again' : 'Verify & continue'}
        </FBButton>
      </div>
    </FBScreen>
  );
}


// ─────────────────────────────────────────────────────────────────────
// US-2 · 90-Tage Dashboard
// ─────────────────────────────────────────────────────────────────────

const RECENT_SESSIONS = [
  { date: 'Mon · May 25', name: 'Push A — Chest, Shoulders', vol: '8,420', sets: 18 },
  { date: 'Sat · May 23', name: 'Pull B — Back, Biceps', vol: '7,180', sets: 16 },
  { date: 'Thu · May 21', name: 'Legs — Squat focus', vol: '11,640', sets: 14 },
  { date: 'Tue · May 19', name: 'Push A — Chest, Shoulders', vol: '8,260', sets: 18 },
  { date: 'Sun · May 17', name: 'Pull B — Back, Biceps', vol: '7,020', sets: 16 },
];

const MUSCLE_DIST = [
  { label: 'Chest', pct: 88, value: '46k' },
  { label: 'Back', pct: 76, value: '40k' },
  { label: 'Legs', pct: 42, value: '22k' },
  { label: 'Shoulders', pct: 58, value: '30k' },
  { label: 'Arms', pct: 64, value: '34k' },
  { label: 'Core', pct: 28, value: '15k' },
];

function FBDashboardScreen({ variant = 'data', onAnalyze, syncBanner = false, analyzeProminence = 'card' }) {
  const isEmpty = variant === 'empty';
  const isOffline = variant === 'offline';

  return (
    <FBScreen padding="0">
      {/* Header */}
      <div style={{ padding: '54px 20px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <FBLabel>Last 90 days</FBLabel>
            <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.6, marginTop: 4 }}>
              Dashboard
            </div>
          </div>
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: FB.card,
            boxShadow: `0 0 0 1px ${FB.border}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="9" r="7" stroke={FB.ink} strokeWidth="1.5"/>
              <path d="M9 4v5l3 2" stroke={FB.ink} strokeWidth="1.5" strokeLinecap="round"/>
            </svg>
          </div>
        </div>

        {/* Sync banner (offline mode) */}
        {isOffline && (
          <div style={{
            marginTop: 14, padding: '10px 12px', borderRadius: 12,
            background: FB.warnSoft, boxShadow: `inset 0 0 0 1px ${FB.warn}40`,
            display: 'flex', alignItems: 'center', gap: 10,
          }}>
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M9 2v4M9 12v4M2 9h4M12 9h4" stroke={FB.warn} strokeWidth="1.6" strokeLinecap="round"/>
              <circle cx="9" cy="9" r="2.5" stroke={FB.warn} strokeWidth="1.6"/>
            </svg>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: -0.1, color: FB.ink }}>
                Showing cached data
              </div>
              <div style={{ fontSize: 11.5, color: FB.ink2, marginTop: 1 }}>
                Last synced 2 h 14 min ago · Hevy unreachable
              </div>
            </div>
            <div style={{ fontSize: 13, fontWeight: 600, color: FB.warn }}>Retry</div>
          </div>
        )}
      </div>

      {isEmpty ? (
        <FBDashboardEmpty />
      ) : (
        <div style={{ padding: '20px 16px 120px' }}>
          {/* Analyze CTA card (prominent) */}
          {analyzeProminence === 'card' && (
            <div style={{
              borderRadius: 18, padding: 18, marginBottom: 16,
              background: FB.ink, color: '#fff', position: 'relative', overflow: 'hidden',
            }}>
              <div style={{
                position: 'absolute', right: -40, top: -40,
                width: 160, height: 160, borderRadius: '50%',
                background: FB.accent, opacity: 0.6, filter: 'blur(30px)',
              }} />
              <div style={{ position: 'relative' }}>
                <FBLabel style={{ color: 'rgba(255,255,255,0.6)' }}>AI · Claude</FBLabel>
                <div style={{ marginTop: 6, fontSize: 19, fontWeight: 600, letterSpacing: -0.3, lineHeight: 1.25 }}>
                  Ready for a progression check?
                </div>
                <div style={{ marginTop: 4, fontSize: 13, color: 'rgba(255,255,255,0.7)', lineHeight: 1.4 }}>
                  Based on your last 30 days, get a concrete recommendation in ~10 s.
                </div>
                <button onClick={onAnalyze} style={{
                  marginTop: 14, height: 40, padding: '0 16px', borderRadius: 10,
                  background: FB.accent, color: '#fff', border: 'none',
                  fontFamily: FB.font, fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
                  cursor: 'pointer',
                }}>Analyze with AI →</button>
              </div>
            </div>
          )}

          {/* Hero stat */}
          <FBCard pad={18} style={{ marginBottom: 12 }}>
            <FBStat
              label="Total volume"
              value="248,420"
              unit="kg"
              delta="↑ 12% vs prior 90 days"
              deltaKind="pos"
            />
            {/* Mini sparkline */}
            <svg width="100%" height="44" viewBox="0 0 320 44" style={{ marginTop: 10 }}>
              <defs>
                <linearGradient id="spk" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={FB.accent} stopOpacity="0.25"/>
                  <stop offset="100%" stopColor={FB.accent} stopOpacity="0"/>
                </linearGradient>
              </defs>
              <path d="M0,32 L20,28 L40,30 L60,22 L80,26 L100,18 L120,24 L140,14 L160,20 L180,12 L200,16 L220,8 L240,14 L260,10 L280,6 L300,12 L320,4"
                stroke={FB.accent} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
              <path d="M0,32 L20,28 L40,30 L60,22 L80,26 L100,18 L120,24 L140,14 L160,20 L180,12 L200,16 L220,8 L240,14 L260,10 L280,6 L300,12 L320,4 L320,44 L0,44 Z"
                fill="url(#spk)"/>
            </svg>
          </FBCard>

          {/* Two stat cards */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <FBCard pad={16}>
              <FBStat label="Avg / week" value="3.4" unit="days" />
            </FBCard>
            <FBCard pad={16}>
              <FBStat label="Sessions" value="42" unit="total" />
            </FBCard>
          </div>

          {/* Muscle distribution */}
          <FBCard pad={18} style={{ marginBottom: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
              <FBLabel>Muscle distribution</FBLabel>
              <div style={{ fontSize: 11, color: FB.muted }}>kg volume</div>
            </div>
            {MUSCLE_DIST.map(b => (
              <FBBar key={b.label} {...b} />
            ))}
            {/* Imbalance hint */}
            <div style={{
              marginTop: 10, padding: '8px 10px', borderRadius: 10,
              background: FB.warnSoft, fontSize: 12, color: FB.ink2,
              display: 'flex', alignItems: 'center', gap: 6,
            }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: FB.warn }} />
              Legs trail chest 2.1× — see AI analysis
            </div>
          </FBCard>

          {/* Recent sessions */}
          <FBCard pad={0} style={{ overflow: 'hidden' }}>
            <div style={{ padding: '14px 16px 6px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <FBLabel>Recent sessions</FBLabel>
              <div style={{ fontSize: 12, color: FB.muted }}>42 total</div>
            </div>
            {RECENT_SESSIONS.map((s, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', padding: '12px 16px',
                borderTop: i === 0 ? 'none' : `1px solid ${FB.divider}`,
              }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 12, color: FB.muted, fontWeight: 500 }}>{s.date}</div>
                  <div style={{ fontSize: 14, fontWeight: 500, marginTop: 2, letterSpacing: -0.2 }}>
                    {s.name}
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.2 }}>
                    {s.vol} <span style={{ color: FB.muted, fontWeight: 500, fontSize: 12 }}>kg</span>
                  </div>
                  <div style={{ fontSize: 11, color: FB.muted }}>{s.sets} sets</div>
                </div>
              </div>
            ))}
          </FBCard>
        </div>
      )}
    </FBScreen>
  );
}

function FBDashboardEmpty() {
  return (
    <div style={{ padding: '60px 32px 0', textAlign: 'center' }}>
      <div style={{
        width: 96, height: 96, borderRadius: 28, margin: '0 auto',
        background: `repeating-linear-gradient(135deg, ${FB.border} 0 8px, transparent 8px 16px), ${FB.card}`,
        border: `1px dashed ${FB.ter}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
          <path d="M6 22h20M9 18l4-6 4 4 6-9" stroke={FB.muted} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </div>
      <div style={{
        marginTop: 22, fontSize: 19, fontWeight: 600, letterSpacing: -0.3,
      }}>No training data for the last 90 days</div>
      <div style={{ marginTop: 8, fontSize: 14, color: FB.muted, lineHeight: 1.45 }}>
        Log a workout in Hevy and pull to refresh. Your dashboard will fill in automatically.
      </div>
      <div style={{
        marginTop: 28, display: 'inline-flex', alignItems: 'center', gap: 8,
        padding: '10px 16px', borderRadius: 999, background: FB.card,
        boxShadow: `0 0 0 1px ${FB.border}`,
        fontSize: 14, fontWeight: 500,
      }}>
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M2 7a5 5 0 019-3M12 7a5 5 0 01-9 3" stroke={FB.ink} strokeWidth="1.6" strokeLinecap="round"/>
          <path d="M9 1l2 3-3 0M5 13l-2-3 3 0" stroke={FB.ink} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
        Pull to refresh
      </div>
    </div>
  );
}


// ─────────────────────────────────────────────────────────────────────
// US-2 · Workout-Detail (2.4) — Drill-down aus «Recent sessions»
// ─────────────────────────────────────────────────────────────────────

const DETAIL_EXERCISES = [
  {
    muscle: 'Chest',
    title: 'Bench Press (Barbell)',
    note: 'Paused first rep of every set.',
    volume: '2.4k', pct: 74, counted: 3,
    sets: [
      { n: 'W', metrics: '60 kg · 10 reps', rpe: null },
      { n: '1', metrics: '102.5 kg · 8 reps', rpe: 'RPE 8' },
      { n: '2', metrics: '102.5 kg · 8 reps', rpe: 'RPE 9' },
      { n: '3', metrics: '102.5 kg · 7 reps', rpe: 'RPE 9.5' },
    ],
  },
  {
    muscle: 'Shoulders',
    title: 'Shoulder Press (Dumbbell)',
    superset: 1,
    volume: '780', pct: 24, counted: 3,
    sets: [
      { n: '1', metrics: '26 kg · 10 reps', rpe: 'RPE 8' },
      { n: '2', metrics: '26 kg · 10 reps', rpe: 'RPE 8' },
      { n: '3', metrics: '26 kg · 10 reps', rpe: 'RPE 8' },
    ],
  },
  {
    // Bodyweight: no weight was logged, so none is shown — never "0 kg".
    muscle: 'Chest',
    title: 'Dips',
    superset: 1,
    volume: '0', pct: 0, counted: 3,
    sets: [
      { n: '1', metrics: '12 reps', rpe: null },
      { n: '2', metrics: '11 reps', rpe: null },
      { n: '3', metrics: '10 reps', rpe: null },
    ],
  },
  {
    // Cardio: distance and time, again with no weight column invented.
    muscle: 'Other',
    title: 'Treadmill',
    volume: '0', pct: 0, counted: 1,
    sets: [
      { n: '1', metrics: '2.4 km · 13:00', rpe: null },
    ],
  },
];

function FBWorkoutDetailScreen({ onBack }) {
  return (
    <FBScreen padding="0">
      {/* Inline nav bar — the screen is pushed, not presented */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 2,
        padding: '54px 16px 10px',
        background: 'rgba(242,241,237,0.92)',
        backdropFilter: 'blur(16px) saturate(180%)',
        WebkitBackdropFilter: 'blur(16px) saturate(180%)',
        borderBottom: `1px solid ${FB.border}`,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <button onClick={onBack} style={{
          display: 'flex', alignItems: 'center', gap: 4,
          border: 'none', background: 'transparent', cursor: 'pointer',
          fontFamily: FB.font, fontSize: 15, fontWeight: 500, color: FB.ink, padding: 0,
        }}>
          <svg width="9" height="15" viewBox="0 0 9 15">
            <path d="M7.5 1L1 7.5 7.5 14" stroke={FB.ink} strokeWidth="2" fill="none"
              strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          Dashboard
        </button>
        <div style={{
          flex: 1, textAlign: 'center', fontSize: 16, fontWeight: 600,
          letterSpacing: -0.2, marginRight: 76,
        }}>Push Day</div>
      </div>

      <div style={{ padding: '12px 16px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* Session header */}
        <FBCard pad={18}>
          <FBLabel>Monday, 25 May 2026</FBLabel>
          <div style={{ marginTop: 8, fontSize: 20, fontWeight: 600, letterSpacing: -0.4 }}>
            Push Day
          </div>
          <div style={{ marginTop: 12 }}>
            <FBStat label="Volume" value="3,138" unit="kg" />
          </div>
          <div style={{
            marginTop: 10, fontSize: 13, color: FB.ink2,
            fontVariantNumeric: 'tabular-nums',
          }}>
            4 exercises · 10 sets · 1 h 12 min
          </div>
        </FBCard>

        {/* Hevy's own session note */}
        <FBCard pad={16}>
          <div style={{ fontSize: 14, color: FB.ink2, lineHeight: 1.45 }}>
            Felt strong, bar speed held up across all top sets.
          </div>
        </FBCard>

        {DETAIL_EXERCISES.map(ex => (
          <FBExerciseCard key={ex.title} {...ex} />
        ))}
      </div>
    </FBScreen>
  );
}

function FBExerciseCard({ muscle, title, note, superset, volume, pct, counted, sets }) {
  const hasVolume = pct > 0;

  return (
    <FBCard pad={16}>
      <FBLabel>{muscle}</FBLabel>
      <div style={{
        marginTop: 4, display: 'flex', alignItems: 'baseline', gap: 8,
      }}>
        <div style={{ flex: 1, fontSize: 17, fontWeight: 600, letterSpacing: -0.3 }}>{title}</div>
        {superset && (
          <div style={{
            padding: '3px 8px', borderRadius: 999,
            background: FB.accentSoft, color: FB.accentInk,
            fontSize: 11, fontWeight: 500,
          }}>Superset {superset}</div>
        )}
      </div>

      {note && (
        <div style={{
          marginTop: 10, padding: 10, borderRadius: 14,
          background: FB.cardSubtle, fontSize: 12, color: FB.ink2, lineHeight: 1.4,
        }}>{note}</div>
      )}

      {/* Share of the session's volume — the FBBar primitive */}
      <div style={{ marginTop: 6 }}>
        {hasVolume ? (
          <FBBar label={`${counted} sets`} pct={pct} value={volume} />
        ) : (
          <div style={{ padding: '7px 0', fontSize: 12, color: FB.muted }}>
            {counted} counted sets
          </div>
        )}
      </div>

      <div style={{ borderTop: `1px solid ${FB.divider}`, marginTop: 4, paddingTop: 4 }}>
        {sets.map((s, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'baseline', gap: 12, padding: '7px 0',
          }}>
            <div style={{
              width: 22, fontSize: 12, fontWeight: 600,
              fontVariantNumeric: 'tabular-nums',
              // Warm-ups are marked, not numbered: they do not count towards
              // the volume printed above.
              color: s.n === 'W' ? FB.warn : FB.muted,
            }}>{s.n}</div>
            <div style={{
              flex: 1, fontSize: 14, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.2,
            }}>{s.metrics}</div>
            {s.rpe && (
              <div style={{ fontSize: 12, color: FB.muted, fontVariantNumeric: 'tabular-nums' }}>
                {s.rpe}
              </div>
            )}
          </div>
        ))}
      </div>
    </FBCard>
  );
}

// ─────────────────────────────────────────────────────────────────────
// US-3 · AI-Analyse auf Knopfdruck
// ─────────────────────────────────────────────────────────────────────

function FBAnalyzeLoadingScreen({ longWait = false, onCancel }) {
  const steps = [
    { label: 'Reading 14 workouts from Hevy', done: true },
    { label: 'Computing volume & muscle balance', done: true },
    { label: 'Asking Claude for recommendations', done: false, current: true },
  ];
  return (
    <FBScreen padding="0" bg={FB.bg}>
      {/* Pseudo-modal sheet effect */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'rgba(14,14,14,0.35)',
      }} />
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, top: 80,
        background: FB.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28,
        padding: '24px 24px 48px', display: 'flex', flexDirection: 'column',
      }}>
        {/* handle */}
        <div style={{
          width: 36, height: 4, borderRadius: 2, background: FB.ter,
          margin: '0 auto 28px',
        }} />

        <FBLabel>AI analysis</FBLabel>
        <div style={{
          marginTop: 6, fontSize: 24, fontWeight: 700, letterSpacing: -0.5, lineHeight: 1.2,
        }}>
          Analyzing your<br/>last 30 days
        </div>

        {/* Steps */}
        <div style={{ marginTop: 36, display: 'flex', flexDirection: 'column', gap: 18 }}>
          {steps.map((s, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              {s.done ? (
                <div style={{
                  width: 22, height: 22, borderRadius: 11, background: FB.accent,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                    <path d="M2 6l3 3 5-6" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                  </svg>
                </div>
              ) : s.current ? (
                <FBSpinner size={22} color={FB.ink} />
              ) : (
                <div style={{
                  width: 22, height: 22, borderRadius: 11,
                  boxShadow: `inset 0 0 0 1.5px ${FB.border}`,
                }} />
              )}
              <div style={{
                fontSize: 15, fontWeight: s.current ? 600 : 500,
                color: s.done ? FB.muted : FB.ink, letterSpacing: -0.2,
              }}>
                {s.label}
                {s.done && <span style={{ marginLeft: 8, color: FB.muted, fontSize: 13 }}>· done</span>}
              </div>
            </div>
          ))}
        </div>

        {/* Long wait notice */}
        {longWait && (
          <div className="fb-fade" style={{
            marginTop: 28, padding: 16, borderRadius: 14, background: FB.card,
            boxShadow: `0 0 0 1px ${FB.border}`,
          }}>
            <div style={{ fontSize: 14, fontWeight: 600, letterSpacing: -0.2 }}>
              Analysis is taking longer than expected
            </div>
            <div style={{ marginTop: 4, fontSize: 13, color: FB.muted, lineHeight: 1.4 }}>
              Claude usually responds in under 15 s. You can cancel and try again.
            </div>
          </div>
        )}

        <div style={{ flex: 1 }} />

        {/* Cancel button (only after 30s) */}
        {longWait && (
          <FBButton kind="secondary" onClick={onCancel}>Cancel analysis</FBButton>
        )}

        <div style={{
          marginTop: longWait ? 12 : 0, textAlign: 'center', fontSize: 12, color: FB.muted,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        }}>
          <FBLockIcon size={11} />
          Only your data is sent to Claude · no benchmarks
        </div>
      </div>
    </FBScreen>
  );
}

function FBAnalysisResultScreen({ variant = 'progression', feedback = null, cooldown = false, onFeedback, onClose }) {
  // variant: 'progression' | 'recovery'
  const recovery = variant === 'recovery';

  return (
    <FBScreen padding="0">
      <div style={{ padding: '54px 20px 120px' }}>
        {/* Top row */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <FBLabel>AI · Claude · just now</FBLabel>
          <button onClick={onClose} style={{
            width: 30, height: 30, borderRadius: 8, border: 'none',
            background: FB.card, boxShadow: `0 0 0 1px ${FB.border}`, cursor: 'pointer',
          }}>
            <svg width="12" height="12" viewBox="0 0 12 12">
              <path d="M2 2l8 8M10 2l-8 8" stroke={FB.ink} strokeWidth="1.8" strokeLinecap="round"/>
            </svg>
          </button>
        </div>

        {/* Headline */}
        <div style={{ marginTop: 10, fontSize: 30, fontWeight: 700, letterSpacing: -0.8, lineHeight: 1.1 }}>
          {recovery
            ? <>Recover<br/>this week.</>
            : <>You're ready<br/>to progress.</>}
        </div>

        {/* Context line (US-6) */}
        <div style={{
          marginTop: 12, padding: '8px 12px', borderRadius: 10,
          background: FB.cardSubtle, boxShadow: `inset 0 0 0 1px ${FB.border}`,
          fontSize: 12, color: FB.ink2,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: FB.accent }} />
          Based on <strong style={{ color: FB.ink, fontWeight: 600 }}>14 Hevy workouts</strong> · last 30 days
        </div>

        {/* Recommendations */}
        <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {recovery ? (
            <RecoveryRecCard />
          ) : (
            <>
              <ProgressionRecCard
                exercise="Bench Press"
                from="60 kg" to="62.5 kg"
                reasoning="3 sessions at 60×5 with RPE ≤7 — clean overload signal."
                muscle="Chest"
              />
              <ProgressionRecCard
                exercise="Back Squat"
                from="80 kg" to="82.5 kg"
                reasoning="Plateau cleared 2 weeks ago, bar speed stable across sets."
                muscle="Legs"
              />
              <ImbalanceRecCard />
            </>
          )}
        </div>

        {/* Disclaimer */}
        <div style={{
          marginTop: 18, fontSize: 11, color: FB.muted, lineHeight: 1.45,
          paddingLeft: 12, borderLeft: `2px solid ${FB.border}`,
        }}>
          FitBuddy is not a medical product. You're responsible for any training change you make.
        </div>
      </div>

      {/* Bottom feedback bar */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        background: 'rgba(248,247,244,0.92)',
        backdropFilter: 'blur(16px) saturate(180%)',
        WebkitBackdropFilter: 'blur(16px) saturate(180%)',
        borderTop: `1px solid ${FB.border}`,
        padding: '14px 16px 44px',
      }}>
        {cooldown ? (
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 13, color: FB.muted, marginBottom: 4 }}>Thanks for the feedback.</div>
            <div style={{ fontSize: 14, fontWeight: 600, letterSpacing: -0.2 }}>
              Next analysis available in <span style={{ fontVariantNumeric: 'tabular-nums' }}>5 h 42 m</span>
            </div>
          </div>
        ) : (
          <>
            <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 8, color: FB.ink2 }}>
              Was this helpful?
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <FBFeedbackBtn
                selected={feedback === 'yes'}
                onClick={() => onFeedback && onFeedback('yes')}
                icon={
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M2 8h2.5v6H2zM4.5 8l3-5.5c.3-.6 1.1-.7 1.5-.2.3.4.3.9.1 1.3L7.5 7h4.6c.8 0 1.4.8 1.2 1.6l-1 4.4c-.2.7-.8 1.2-1.5 1.2H4.5z"
                      stroke={feedback === 'yes' ? '#fff' : FB.ink} strokeWidth="1.2" strokeLinejoin="round"
                      fill={feedback === 'yes' ? '#fff' : 'none'}/>
                  </svg>
                }
                label="Helpful"
                accent
              />
              <FBFeedbackBtn
                selected={feedback === 'no'}
                onClick={() => onFeedback && onFeedback('no')}
                icon={
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M2 8h2.5V2H2zM4.5 8l3 5.5c.3.6 1.1.7 1.5.2.3-.4.3-.9.1-1.3L7.5 9h4.6c.8 0 1.4-.8 1.2-1.6l-1-4.4C12.1 2.3 11.5 2 10.8 2H4.5z"
                      stroke={feedback === 'no' ? '#fff' : FB.ink} strokeWidth="1.2" strokeLinejoin="round"
                      fill={feedback === 'no' ? '#fff' : 'none'}/>
                  </svg>
                }
                label="Not helpful"
              />
            </div>
          </>
        )}
      </div>
    </FBScreen>
  );
}

function FBFeedbackBtn({ selected, onClick, icon, label, accent }) {
  return (
    <button onClick={onClick} style={{
      flex: 1, height: 44, borderRadius: 12,
      background: selected ? (accent ? FB.accent : FB.ink) : FB.card,
      color: selected ? '#fff' : FB.ink,
      boxShadow: selected ? 'none' : `0 0 0 1px ${FB.border}`,
      border: 'none', cursor: 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      fontFamily: FB.font, fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
    }}>
      {icon}
      {label}
    </button>
  );
}

function ProgressionRecCard({ exercise, from, to, reasoning, muscle }) {
  return (
    <FBCard pad={16}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{
          padding: '3px 8px', borderRadius: 999, background: FB.accentSoft,
          fontSize: 11, fontWeight: 600, color: FB.accentInk, letterSpacing: 0.2,
          textTransform: 'uppercase',
          boxShadow: `inset 0 0 0 1px ${FB.accentBorder}`,
        }}>↑ Increase</div>
        <div style={{ fontSize: 11, color: FB.muted, fontWeight: 500 }}>{muscle}</div>
      </div>

      <div style={{ fontSize: 17, fontWeight: 600, letterSpacing: -0.3 }}>{exercise}</div>

      <div style={{
        marginTop: 10, display: 'flex', alignItems: 'baseline', gap: 8,
        fontVariantNumeric: 'tabular-nums',
      }}>
        <span style={{ fontSize: 14, color: FB.muted, textDecoration: 'line-through' }}>{from}</span>
        <svg width="14" height="14" viewBox="0 0 14 14"><path d="M2 7h10M8 3l4 4-4 4" stroke={FB.muted} strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>
        <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: -0.5, color: FB.accent }}>{to}</span>
        <span style={{ fontSize: 12, color: FB.muted, marginLeft: 'auto', fontWeight: 500 }}>+2.5 kg</span>
      </div>

      <div style={{
        marginTop: 10, fontSize: 13, color: FB.ink2, lineHeight: 1.45,
        paddingTop: 10, borderTop: `1px solid ${FB.divider}`,
      }}>
        {reasoning}
      </div>
    </FBCard>
  );
}

function ImbalanceRecCard() {
  return (
    <FBCard pad={16}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{
          padding: '3px 8px', borderRadius: 999, background: FB.warnSoft,
          fontSize: 11, fontWeight: 600, color: FB.ink, letterSpacing: 0.2,
          textTransform: 'uppercase',
          boxShadow: `inset 0 0 0 1px ${FB.warn}40`,
        }}>! Imbalance</div>
        <div style={{ fontSize: 11, color: FB.muted, fontWeight: 500 }}>Chest vs Legs</div>
      </div>

      <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2, lineHeight: 1.35 }}>
        You're training chest 3×/week but legs only 1×/week.
      </div>

      <div style={{
        marginTop: 10, fontSize: 13, color: FB.ink2, lineHeight: 1.45,
      }}>
        Add a second leg session this week (squat or RDL focus) before pushing chest further.
      </div>

      {/* Mini bar comparison */}
      <div style={{ marginTop: 12, display: 'flex', gap: 8 }}>
        <MiniMuscle label="Chest" pct={88} count="3×/wk" color={FB.accent} />
        <MiniMuscle label="Legs" pct={32} count="1×/wk" color={FB.warn} />
      </div>
    </FBCard>
  );
}

function MiniMuscle({ label, pct, count, color }) {
  return (
    <div style={{
      flex: 1, padding: '10px 12px', borderRadius: 10, background: FB.cardSubtle,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: -0.1 }}>{label}</div>
        <div style={{ fontSize: 11, color: FB.muted, fontWeight: 500 }}>{count}</div>
      </div>
      <div style={{
        marginTop: 8, height: 6, borderRadius: 3, background: FB.border, overflow: 'hidden',
      }}>
        <div style={{ width: `${pct}%`, height: '100%', background: color }} />
      </div>
    </div>
  );
}

function RecoveryRecCard() {
  return (
    <FBCard pad={16} style={{
      background: FB.warnSoft, boxShadow: `0 0 0 1px ${FB.warn}40`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{
          padding: '3px 8px', borderRadius: 999, background: '#fff',
          fontSize: 11, fontWeight: 600, color: FB.warn, letterSpacing: 0.2,
          textTransform: 'uppercase',
          boxShadow: `inset 0 0 0 1px ${FB.warn}40`,
        }}>⏸ Recovery</div>
      </div>

      <div style={{ fontSize: 17, fontWeight: 600, letterSpacing: -0.3, lineHeight: 1.3 }}>
        You trained 6 of the last 7 days.
      </div>

      <div style={{ marginTop: 10, fontSize: 13, color: FB.ink2, lineHeight: 1.5 }}>
        Before adding intensity to chest or legs, take{' '}
        <strong style={{ color: FB.ink, fontWeight: 600 }}>2 rest days</strong>{' '}
        and a deload session (sets ×0.6 volume).
        Your CNS load is high — pushing now usually flattens next week.
      </div>

      <div style={{
        marginTop: 14, padding: 12, borderRadius: 10, background: '#fff',
        display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10,
      }}>
        {[
          ['Sessions / 7d', '6'],
          ['Avg RPE', '8.2'],
          ['Suggested rest', '48h'],
        ].map(([k, v]) => (
          <div key={k}>
            <div style={{ fontSize: 10, color: FB.muted, fontWeight: 500, letterSpacing: 0.4, textTransform: 'uppercase' }}>{k}</div>
            <div style={{ marginTop: 2, fontSize: 18, fontWeight: 700, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.4 }}>{v}</div>
          </div>
        ))}
      </div>
    </FBCard>
  );
}

Object.assign(window, {
  FBWelcomeScreen, FBKeyEntryScreen,
  FBDashboardScreen, FBWorkoutDetailScreen,
  FBAnalyzeLoadingScreen, FBAnalysisResultScreen,
});
