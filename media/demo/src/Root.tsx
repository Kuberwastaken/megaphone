import React from 'react';
import {Composition} from 'remotion';
import {MegaphoneIntro} from './MegaphoneIntro';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="MegaphoneIntro"
    component={MegaphoneIntro}
    durationInFrames={360}
    fps={30}
    width={1200}
    height={750}
  />
);
