import { parseSseEvent } from './sse';
const API = import.meta.env.VITE_API_URL || '';
export type User = { id: number; email: string };
export type Conversation = { id: number; title: string; created_at: string; updated_at: string };
export type Message = { id: number; role: 'user' | 'assistant'; content: string; created_at: string };
export function token() { return localStorage.getItem('genai_token'); }
export function setToken(value: string | null) { value ? localStorage.setItem('genai_token', value) : localStorage.removeItem('genai_token'); }
async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API}${path}`, { ...init, headers: { 'Content-Type': 'application/json', ...(token() ? { Authorization: `Bearer ${token()}` } : {}), ...init.headers } });
  if (!response.ok) { const body = await response.json().catch(() => ({})); throw new Error(body.detail || `Request failed (${response.status})`); }
  if (response.status === 204) return undefined as T;
  return response.json();
}
export const api = {
  auth: (path: 'login' | 'register', email: string, password: string) => request<{access_token:string;user:User}>(`/api/auth/${path}`, { method:'POST', body:JSON.stringify({email,password}) }),
  me: () => request<User>('/api/auth/me'),
  conversations: () => request<Conversation[]>('/api/conversations'),
  createConversation: () => request<Conversation>('/api/conversations', {method:'POST'}),
  messages: (id:number) => request<Message[]>(`/api/conversations/${id}/messages`),
  deleteConversation: (id:number) => request<void>(`/api/conversations/${id}`, {method:'DELETE'}),
  async stream(id:number, content:string, onToken:(s:string)=>void) {
    const response = await fetch(`${API}/api/conversations/${id}/chat`, { method:'POST', headers:{'Content-Type':'application/json', Authorization:`Bearer ${token()}`}, body:JSON.stringify({content}) });
    if (!response.ok || !response.body) { const body = await response.json().catch(()=>({})); throw new Error(body.detail || 'Unable to start response'); }
    const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = '';
    while (true) {
      const {value,done} = await reader.read(); if (done) break;
      buffer += decoder.decode(value,{stream:true}); const events = buffer.split('\n\n'); buffer = events.pop() || '';
      for (const event of events) { const data = parseSseEvent(event); if (!data) continue; if (data.error) throw new Error(data.error); if (data.token) onToken(data.token); }
    }
  }
};
