// Misma imagen en Docker Desktop y OCI: el navegador usa el host visitado.
export const API_Back_Url = typeof window !== 'undefined'
  ? (window.location.port
      ? `${window.location.protocol}//${window.location.hostname}:3100`
      : `${window.location.origin}/api`)
  : (process.env.INTERNAL_API_URL || 'http://backend:3000');
