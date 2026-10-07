// A simple signature pad: strokes drawn with a finger, kept as an SVG path.

import { useEffect, useState } from 'react';
import { PanResponder, StyleSheet, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';

import { radius, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

import { Button, Txt } from './ui';

interface Pad {
  strokes: string[];
  live: string;
}

const pt = (x: number, y: number) => `${x.toFixed(1)} ${y.toFixed(1)}`;

export function SignaturePad({ onChange }: { onChange: (path: string) => void }) {
  const p = usePalette();
  const [pad, setPad] = useState<Pad>({ strokes: [], live: '' });
  const [responder] = useState(() =>
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: (e) => {
        const { locationX, locationY } = e.nativeEvent;
        setPad((s) => ({ ...s, live: `M${pt(locationX, locationY)}` }));
      },
      onPanResponderMove: (e) => {
        const { locationX, locationY } = e.nativeEvent;
        setPad((s) => ({ ...s, live: `${s.live} L${pt(locationX, locationY)}` }));
      },
      onPanResponderRelease: () => {
        setPad((s) => ({ strokes: s.live.includes('L') ? [...s.strokes, s.live] : s.strokes, live: '' }));
      },
    }),
  );

  useEffect(() => {
    onChange(pad.strokes.join(' '));
  }, [pad.strokes, onChange]);

  return (
    <View style={{ gap: space.sm }}>
      <View {...responder.panHandlers} style={[styles.pad, { borderColor: p.border, backgroundColor: p.surface }]} accessibilityLabel="Signature pad. Sign with your finger." accessible>
        <Svg width="100%" height="100%">
          {pad.strokes.map((d, i) => (
            <Path key={i} d={d} stroke={p.text} strokeWidth={2.5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
          ))}
          {pad.live ? <Path d={pad.live} stroke={p.text} strokeWidth={2.5} fill="none" strokeLinecap="round" strokeLinejoin="round" /> : null}
        </Svg>
        {pad.strokes.length === 0 && !pad.live ? (
          <View style={styles.hint} pointerEvents="none">
            <Txt variant="small" muted>
              Sign here
            </Txt>
          </View>
        ) : null}
      </View>
      <Button title="Clear signature" kind="ghost" compact onPress={() => setPad({ strokes: [], live: '' })} />
    </View>
  );
}

const styles = StyleSheet.create({
  pad: { height: 160, borderWidth: 1, borderRadius: radius.md, overflow: 'hidden' },
  hint: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
});
