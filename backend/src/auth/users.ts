export type AppUser = {
  id: string;
  email: string;
  password: string;
  role: 'diver' | 'scientist';
};

// Intentionally hardcoded. This is an educational prototype, not production auth.
export const USERS: AppUser[] = [
  {
    id: 'user-diver',
    email: 'diver@example.com',
    password: 'password',
    role: 'diver',
  },
  {
    id: 'user-scientist',
    email: 'scientist@example.com',
    password: 'password',
    role: 'scientist',
  },
];
