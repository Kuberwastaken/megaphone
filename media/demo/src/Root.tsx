import React from 'react';
import {Composition} from 'remotion';
import {MegaphoneIntro} from './MegaphoneIntro';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="MegaphoneIntro"
    component={MegaphoneIntro}
    durationInFrames={77}
    fps={25}
    width={1200}
    height={780}
  />
);
