pipeline {
    agent {
        docker {
            image 'maroki92/maven-jdk21-trivy:latest' // image Docker custom avec Maven 3.9 + JDK21 + Trivy
            args '-v $HOME/.m2:/root/.m2 -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    environment {
        // Configuration de base
        APP_NAME = 'demo'
        DOCKER_REGISTRY = 'maroki92'  // ou votre registry
        IMAGE_NAME = "${DOCKER_REGISTRY}/${APP_NAME}"

        // Kubernetes
        KUBECONFIG = '/var/jenkins_home/.kube/config'
        K8S_NAMESPACE_DEV = 'dev'
        K8S_NAMESPACE_PROD = 'production'

        // Maven
        MAVEN_OPTS = '-Dmaven.repo.local=/var/jenkins_home/.m2/repository'
    }

    /*tools {
        maven 'Maven-3.9'  // Configurez dans Jenkins Global Tools
    }*/

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.BUILD_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        stage('Test & Build') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'mvn clean test'
                    }
                    post {
                        always {
                            junit 'target/surefire-reports/*.xml'
                            //publishCoverage adapters: [jacocoAdapter('target/site/jacoco/jacoco.xml')]
                        }
                    }
                }

                stage('Code Quality') {
                    steps {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                            sh """
                                mvn sonar:sonar \
                                  -Dsonar.projectKey=${APP_NAME} \
                                  -Dsonar.host.url=http://sonarqube:9000 \
                                  -Dsonar.login=$SONAR_TOKEN
                            """
                        }
                    }
                }
            }
        }

        stage('Package Application') {
            steps {
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: false
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def image = docker.build("${IMAGE_NAME}:${BUILD_TAG}")
                    docker.withRegistry('', 'docker-registry-credentials') {
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh """
                    mkdir -p trivy-reports
                    trivy image --exit-code 0 --severity HIGH,CRITICAL \
                        --format json --output trivy-reports/trivy-report.json \
                        ${IMAGE_NAME}:${BUILD_TAG}
                    trivy convert --format template --template @contrib/html.tpl \
                        trivy-reports/trivy-report.json > trivy-reports/trivy-report.html
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: true

                    publishHTML([
                        reportDir: 'trivy-reports',
                        reportFiles: 'trivy-report.html',
                        reportName: 'Trivy Security Report',
                        keepAll: true,
                        alwaysLinkToLastBuild: true,
                        allowMissing: true
                    ])
                }
            }
        }

        /*stage('Deploy to Dev') {
            when {
                anyOf {
                    branch 'develop'
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                script {
                    deployToK8s('dev', env.BUILD_TAG)
                }
            }
        }*/

        /*stage('Integration Tests') {
            when {
                anyOf {
                    branch 'develop'
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                script {
                    // Attendre que le déploiement soit prêt
                    sh """
                        kubectl wait --for=condition=available --timeout=300s \\
                        deployment/dev-spring-app -n ${K8S_NAMESPACE_DEV}
                    """

                    // Tests d'intégration
                    sh """
                        sleep 30
                        kubectl get pods -n ${K8S_NAMESPACE_DEV}
                        # Ajoutez vos tests d'intégration ici
                    """
                }
            }
        }*/

        /*stage('Deploy to Production') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                script {
                    // Demande d'approbation pour la production
                    timeout(time: 10, unit: 'MINUTES') {
                        input message: 'Déployer en production?',
                              submitter: 'admin,deployer'
                    }

                    deployToK8s('prod', env.BUILD_TAG)
                }
            }
        }*/

        /*stage('Smoke Tests Prod') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                script {
                    sh """
                        kubectl wait --for=condition=available --timeout=300s \\
                        deployment/prod-spring-app -n ${K8S_NAMESPACE_PROD}

                        # Tests de fumée
                        sleep 30
                        echo "Application déployée en production avec succès!"
                    """
                }
            }
        }*/
    }

    post {
        always {
            // Nettoyage
            sh 'docker system prune -f'

            // Archivage des logs
            archiveArtifacts artifacts: 'target/logs/**/*.log',
                           allowEmptyArchive: true
        }

        success {
            echo "✅ Pipeline réussi pour ${env.BRANCH_NAME}"
            // Notification Slack/Teams (optionnel)
            // slackSend channel: '#deployments',
            //          message: "✅ Déploiement réussi: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
        }

        failure {
            echo "❌ Pipeline échoué pour ${env.BRANCH_NAME}"
            // Rollback automatique en cas d'échec
            script {
                if (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master') {
                    sh """
                        echo "Rollback automatique..."
                        kubectl rollout undo deployment/prod-spring-app -n ${K8S_NAMESPACE_PROD} || true
                    """
                }
            }
        }

        unstable {
            echo "⚠️ Pipeline instable - vérifiez les tests"
        }
    }
}

// Fonction helper pour le déploiement
def deployToK8s(environment, imageTag) {
    sh """
        cd k8s/overlays/${environment}

        # Mise à jour de l'image
        kustomize edit set image spring-app=${IMAGE_NAME}:${imageTag}

        # Application des manifests
        kustomize build . | kubectl apply -f -

        # Vérification du déploiement
        kubectl rollout status deployment/${environment}-spring-app -n ${environment == 'dev' ? K8S_NAMESPACE_DEV : K8S_NAMESPACE_PROD}
    """
}