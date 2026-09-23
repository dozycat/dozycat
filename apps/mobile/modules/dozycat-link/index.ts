import { requireOptionalNativeModule, NativeModule } from 'expo';
export type LinkStatus = {
  phase: 'idle' | 'starting' | 'waiting' | 'discovering' | 'connecting' | 'handshaking' | 'compare' | 'connected' | 'error';
  fingerprint: string;
  message: string;
  paired: boolean;
  approved: boolean;
};
type LinkEvents = { onStatus: (status: LinkStatus) => void };
declare class DozycatLink extends NativeModule<LinkEvents> {
  status(): Promise<LinkStatus>;
  pair(invite: string): Promise<void>;
  approve(fingerprint: string): Promise<void>;
  reconnect(): Promise<void>;
  cancel(): Promise<void>;
  removeDevice(): Promise<void>;
}
// Expo Go, Web and Android stay usable without falsely reporting a secure connection.
export default requireOptionalNativeModule<DozycatLink>('DozycatLink');
