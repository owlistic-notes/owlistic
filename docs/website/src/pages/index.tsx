import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import clsx from 'clsx';

import styles from './index.module.css';

function HomepageHeader() {
  return (
    <header className={clsx('hero hero--secondary', styles.heroBanner)}>
      <div className="container">
          <img src={'img/logo/owlistic-w-text.png'} width={'25%'} height={'25%'} alt="Owlistic logo" />
          <Heading as="h6" className="hero__subtitle">
            An "Owlistic" notetaking app to easily organize and manage your notes and tasks!
          </Heading>
        <div className={styles.buttons}>
          <Link
            className="button button--primary button--lg margin--right"
            to="/docs/overview/quick-start">
            Get Started
          </Link>
          <Link
            className="button button--primary button--lg"
            to="/roadmap">
            Roadmap
          </Link>
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout title="Owlistic">
      <HomepageHeader />
    </Layout>
  );
}
