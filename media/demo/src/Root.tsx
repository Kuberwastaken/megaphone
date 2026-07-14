import React from 'react';
import {Composition} from 'remotion';
import {demoDuration, MegaphoneIntro} from './MegaphoneIntro';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="MegaphoneIntro"
    component={MegaphoneIntro}
    durationInFrames={demoDuration}
    fps={30}
    width={1200}
    height={764}
  />
);
