import { JSX } from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';

function HomepageHeader() {
  return (
    <header>
      <div className="top-[calc(12%)]  md:top-[calc(30%)] h-screen w-full absolute -z-10">
        <img src={'img/logo/owlistic.svg'} className="h-[110%] w-[110%] mb-2 antialiased -z-10" alt="Owlistic logo" />
        <div className="w-full h-[120vh] absolute left-0 top-0 backdrop-blur-3xl"></div>
      </div>
      <section className="text-center pt-12 sm:pt-24">
        <div className="mt-8">
          <p className="text-3xl md:text-5xl sm:leading-tight mb-1 font-extrabold text-black/90 dark:text-white px-4">
            🦉 Owlistic is an open-source notetaking app with real-time sync 🔄⚡️🚀
          </p>
          <p className="max-w-1/4 m-auto mt-4 px-4 text-lg text-gray-700 dark:text-gray-100">
            Easily organize, and manage your notes and tasks on your own server.
          </p>
        </div>
        <div className="flex flex-col sm:flex-row place-items-center place-content-center mt-9 gap-4 ">
          <Link
            className="flex place-items-center place-content-center py-3 px-8 border rounded-xl no-underline hover:no-underline text-white hover:text-gray-50 font-bold"
            to="docs/overview/quick-start"
          >
            Get Started
          </Link>
        </div>
        <div className="flex flex-col sm:flex-row place-items-center place-content-center mt-9 gap-4 ">
          <Link
            className="flex place-items-center place-content-center py-3 px-8 border rounded-xl no-underline hover:no-underline text-white hover:text-gray-50 font-bold"
            to="docs/overview/quick-start"
          >
            Roadmap
          </Link>
        </div>
      </section>
    </header>
  );
}

export default function Home(): JSX.Element {
  return (
    <Layout title="Owlistic" noFooter={true}>
      <HomepageHeader />
      <div className="flex flex-col place-items-center text-center place-content-center py-8">
        <p>This project is available under GNU AGPL v3 license.</p>
      </div>
    </Layout>
  );
}
