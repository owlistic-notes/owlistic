import type { ReactNode } from 'react';
import * as mdiIcons from '@mdi/js';
import Icon from '@mdi/react';

import styles from './styles.module.css';

export type Item = {
  icon: string;
  iconColor: string;
  title: string;
  description?: string;
  link?: { url: string; text: string };
  done?: false;
  getDateLabel: (language: string) => string;
};

interface Props {
  items: Item[];
}

export function Timeline({ items }: Props): ReactNode {
  return (
    <ul className={styles.timeline}>
      {items.map((item, index) => {
        const isFirst = index === 0;
        const isLast = index === items.length - 1;
        const done = item.done ?? true;
        const dateLabel = item.getDateLabel('en-US');
        const timelineIcon = done ? mdiIcons.mdiCheckboxMarkedCircle : mdiIcons.mdiCheckboxBlankCircle;
        const cardIcon = item.icon;

        return (
          <li key={index} className={styles.timelineItem}>
            <div className={styles.date}>{dateLabel}</div>

            <div className={styles.lineWrapper}>
              {!isLast && <div className={`${styles.line} ${styles.lineTop}`} />}
              <div className={styles.circle}>
              <Icon className={styles.icon}path={timelineIcon} size={1.25} />
              </div>
              {!isFirst && <div className={`${styles.line} ${styles.lineBottom}`} />}
            </div>

            <section className={styles.card}>
              <div className={styles.cardLeft}>
                <div className={styles.cardTitle}>
                  {cardIcon === 'owlistic' ? (
                    <img src="/img/logo/owlistic.svg" height="30" />
                  ) : (
                    <Icon path={cardIcon} size={1} color={item.iconColor} />
                  )}
                  <span>{item.title}</span>
                </div>
                <p className={styles.cardDesc}>{item.description}</p>
              </div>

              <div className={styles.cardRight}>
                {item.link && (
                  <a className={styles.link} href={item.link.url} target="_blank" rel="noopener">
                    [{item.link.text}]
                  </a>
                )}
                <div className={styles.cardDateMobile}>{dateLabel}</div>
              </div>
            </section>
          </li>
        );
      })}
    </ul>
  );
}