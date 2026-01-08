# Backstage Company Templates

Welcome to the `company-templates` library! This repository houses the global software templates for our company's Backstage integrations.

## 🌟 Overview

Our aim is to provide standardized software templates to streamline the development and integration process within Backstage. Your contributions play a crucial role in ensuring that these templates are versatile, robust, and up-to-date.

## 🚀 Getting Started

1. **Clone the Repository**: 
   - Before making changes, ensure you've cloned the repository from GitHub. [Click here](https://github.com/famibo/company-templates) to get to the repository.

3. **Create a New Branch**
    - Always work on a new branch for each feature or fix:
  ```
  git checkout -b <branch-name>
  ```

## 📝 Contributing Guidelines

### General

- Ensure your changes align with the project's coding standards and guidelines.
- Write clear and detailed commit messages.
- Before submitting a pull request, ensure you've tested your changes thoroughly.
- Include comments in your code where necessary.

### Repository Structure

#### Directories

The repository is set up as a mono repository. Every team is invited to contribute by adding Software Templates and documentation. Each Software Template should be created inside the `/templates` directory.

#### Naming Scheme

In order to distinguish the different software templates, each template must be created with the following naming scheme:
```
<team-name-without-dashes>-<software-template-name>-template
```
- The team name is written in all-lowercase and without any dashes
- The software template name is written in lowercase and contains dashes instead of whitespaces. `template` must not be part of the software template name
- Mandatory `-template` suffix after the template name

#### Example

- Let's say the **Dvorak Dev** team wants to write a software template named **Alice**.
- They create their software template in the following directory `/templates/dvorakdev-alice-template` and make sure that their `template.yaml` configuration file is in the root of said directory.

## 🛠 Tools & Technologies

- [Backstage](https://backstage.io/)
- [Azure DevOps](https://dev.azure.com/)
- [GitHub](https://github.com/)

## 🤝 Stay Connected

For any questions, reach out to the maintainers or open an issue. We value your feedback and contributions!
