import Controller from '@ember/controller';
import { inject as service } from '@ember/service';

export default class RunController extends Controller {
  @service router;

  queryParams = ['template'];

  onSubmit(id, namespace) {
    this.router.transitionTo('jobs.job', `${id}@${namespace || 'default'}`);
  }
}