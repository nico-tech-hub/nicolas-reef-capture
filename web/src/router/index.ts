import { createRouter, createWebHistory } from 'vue-router';
import { getToken } from '../api';
import DashboardView from '../views/DashboardView.vue';
import LoginView from '../views/LoginView.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: LoginView, meta: { public: true } },
    { path: '/photos', component: DashboardView },
    { path: '/photos/:id', component: DashboardView },
    { path: '/', redirect: '/photos' },
  ],
});

router.beforeEach((to) => {
  const authed = Boolean(getToken());
  if (!authed && !to.meta.public) {
    return '/login';
  }
  if (authed && to.path === '/login') {
    return '/photos';
  }
});

export default router;
