import React, { Component } from 'react';
import { BrowserRouter as Router, Route } from 'react-router-dom';
import { Provider } from 'react-redux';
import store from './store';
import { setCurrentUser } from './actions/authActions';
import Login from './components/login/Login';
import UserProfile from './components/profile/UserProfile';
import InvitePage from './components/invite/InvitePage';
import InviteUser from './components/invite/InviteUser';
import ConfirmInvite from './components/invite/ConfirmInvite';
import UserList from './components/users/UserList';
import Logout from './components/users/logout';
import PrivateRoute from './components/common/PrivateRoute';
import AdminRoute from './components/common/AdminRoute';
import EditProfile from './components/profile/EditProfile';
import Dashboard from './components/dashboard/Dashboard';
import CompanyOrders from './components/orders/CompanyOrders';
import OrderDetails from './components/orders/OrderDetails';
import AdminLogin from './components/login/AdminLogin';
import ForgotPassword from './components/forgotPassword/ForgotPassword';
import ResetPassword from './components/forgotPassword/ResetPassword';
import InvitedMeeting from './components/dashboard/InvitedMeeting';
import ErrorBoundary from './components/common/ErrorBoundary';
import GenericMeeting from './components/meetings/GenericMeeting';
import 'core-js';
import { withTranslation } from 'react-i18next';
import { TRANSLATE_I18N } from "./actions/types";
// import ReactGA from 'react-ga';
import Reports from './components/reports/MetaReports';
import Account from './components/account/index';
import { hotjar } from 'react-hotjar';
import dayjs from 'dayjs';
import duration from 'dayjs/plugin/duration';
import customParseFormat from 'dayjs/plugin/customParseFormat';
import relativeTime from 'dayjs/plugin/relativeTime';
import timezone from 'dayjs/plugin/timezone';
import utc from 'dayjs/plugin/utc';
import advancedFormat from 'dayjs/plugin/advancedFormat';
import DeliveriesInRage from './components/dashboard/DeliveriesInRange';
import RequestUser from './components/signup/RequestUser';
import SignupConfirmation from './components/invite/SignupConfirmation';

// Check for headers
if (localStorage.headers) {
  store.dispatch(setCurrentUser(localStorage.headers));
}
class App extends Component<any, any> {

  constructor(props: any) {
    super(props);
    dayjs.extend(customParseFormat);
    dayjs.extend(duration);
    dayjs.extend(relativeTime);
    dayjs.extend(timezone);
    dayjs.extend(utc);
    dayjs.extend(advancedFormat);
  }

  componentDidMount() {
    if (process.env.REACT_APP_ENVIRONMENT === 'production') {
      hotjar.initialize(1942393, 6);
      console.log("hotjar env testing", process.env.REACT_APP_ENVIRONMENT)
    }
    this.props.i18n.changeLanguage(window.navigator.language);
    store.dispatch({
      type: TRANSLATE_I18N,
      payload: this.props
    });
    if (process.env.REACT_APP_ENVIRONMENT === 'production') {
      let globalWindow: any = window;
      globalWindow.dataLayer = globalWindow.dataLayer || [];
      function gtag(..._args: unknown[]) { globalWindow.dataLayer.push(arguments); }
      gtag('js', new Date());
      gtag('config', 'G-PF7J0FRY8P');
      // ReactGA.initialize('G-PF7J0FRY8P');
      // ReactGA.pageview(window.location.pathname + window.location.search);
    }
  }
  render() {
    return (
      <Provider store={store}>
        <Router>
          <ErrorBoundary i18n={this.props.i18n}>
            <React.Fragment>
              {localStorage.getItem('headers') ?
                <PrivateRoute exact path='/dashboard/:date/:meetingId?' component={Dashboard} />
               :
                <Route exact path='/dashboard/:date/:token' component={InvitedMeeting} />
              }
              <Route exact path='/user/signup' component={RequestUser} />
              <PrivateRoute exact path='/signup' component={UserProfile} />
              <PrivateRoute exact path='/dashboard' component={DeliveriesInRage} />
              <Route exact path='/meeting/:id/:token' component={GenericMeeting} />
              <Route exact path='/admin-login/:token' component={AdminLogin} />
              <Route exact path='/' component={Login} />
              <Route exact path='/forgot_password' component={ForgotPassword} />
              <Route exact path='/reset_password' component={ResetPassword} />
              <Route exact path='/confirm-signup' component={SignupConfirmation} />
              <PrivateRoute exact path='/profile/:type?' component={EditProfile} />
              <Route exact path='/user/invite/invite_code/:inviteToken' component={InvitePage} />
              <AdminRoute exact path='/invite-user' component={InviteUser} />
              <AdminRoute exact path='/confirm-invite' component={ConfirmInvite} />
              <AdminRoute exact path="/users" component={UserList} />
              <PrivateRoute exact path='/order-history/:date?/:endDate?' component={CompanyOrders} />
              <PrivateRoute exact path='/orders/details/:runningmenu_id' component={OrderDetails} />
              <AdminRoute exact path='/reports' component={Reports} />
              <AdminRoute exact path='/account/:company_id?' component={Account} />
              <Route exact path='/logout' component={Logout} />
            </React.Fragment>
          </ErrorBoundary>
        </Router>
      </Provider>
    );
  }
}
export default withTranslation()(App);