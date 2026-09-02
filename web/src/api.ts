/// create a type for the photo
export type Photo = {
  id: string;
  userId: string;
  userEmail: string;
  originalName: string;
  status: string;
  processingStatus: string;
  validationStatus: string;
  retryCount: number;
  version: number;
  classification: string | null;
  confidence: number | null;
  createdAt: string;
};

/// create a constant for the token key
const TOKEN_KEY = 'reefcapture.token';

/// create a function to get the token
export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

/// create a function to clear the token
export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

/// create a function to request the API
async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  const token = getToken();
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  if (init.body && !(init.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  /// fetch the API
  const response = await fetch(path, { ...init, headers });
  const payload = await response.json().catch(() => ({}));

  if (!response.ok) {
    const error = new Error(payload.message ?? `HTTP ${response.status}`) as Error & { status: number };
    error.status = response.status;
    throw error;
  }
  return payload as T;
}

/// create a function to login the user
export async function login(email: string, password: string): Promise<void> {
  const payload = await request<{ accessToken: string }>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  localStorage.setItem(TOKEN_KEY, payload.accessToken);
}

/// create a function to list the photos
export function listPhotos(): Promise<Photo[]> {
  return request<Photo[]>('/photos');
}

/// create a function to validate the photo
export function validatePhoto(id: string, version: number, approved: boolean): Promise<Photo> {
  return request<Photo>(`/photos/${id}/validate`, {
    method: 'POST',
    body: JSON.stringify({ version, approved }),
  });
}

/// create a function to retry the photo
export function retryPhoto(id: string): Promise<Photo> {
  return request<Photo>(`/photos/${id}/retry`, { method: 'POST' });
}

/// create a function to get the photo file URL
export async function photoFileUrl(id: string): Promise<string> {
  const token = getToken();
  const response = await fetch(`/photos/${id}/file`, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) {
    throw new Error('Could not load photo');
  }
  const blob = await response.blob();
  const head = new Uint8Array(await blob.slice(0, 2).arrayBuffer());
  if (blob.size < 2 || head[0] !== 255 || head[1] !== 216) {
    throw new Error('Could not load photo');
  }
  return URL.createObjectURL(blob);
}
